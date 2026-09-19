import Foundation

/// Orchestrates dedup -> extract -> understand -> embed -> graph write -> relate ->
/// Finder-tag write -> confidence branch, for one file. Shared by the live watcher
/// (Flow A) and the backfill command (Flow B) — plan.md section 5.
final class Pipeline {
    let store: GraphStore
    let router: ProviderRouter
    let settings: SettingsStore

    // Guards against the same path being processed twice concurrently. The AI call
    // alone can take 1-3+ minutes with local Ollama (see OllamaProvider) — that's a
    // wide window for a file to get re-saved (an export tool re-writing a WIP file,
    // a browser finishing a partial download in stages, etc.) and trigger a second,
    // overlapping run before the first has inserted its node. Without this, both
    // runs pass the dedup check (nodeExists is false for both, since neither has
    // inserted yet), both do a full duplicate AI call, and the loser's INSERT hits
    // the nodes.content_hash UNIQUE constraint — GraphStore now recovers gracefully
    // from that, but preventing the wasted duplicate call in the first place is
    // better than merely surviving it.
    private var inFlightPaths = Set<String>()
    private let inFlightLock = NSLock()

    init(store: GraphStore, router: ProviderRouter, settings: SettingsStore) {
        self.store = store
        self.router = router
        self.settings = settings
    }

    /// - Parameter isBackfill: backfill never moves/renames (plan.md Flow B) — this
    ///   flag only affects logging/status semantics, since this MVP doesn't auto-move
    ///   files at all outside of an explicit review/command action (section 8).
    @discardableResult
    func process(fileAt url: URL, isBackfill: Bool = false) async -> Node? {
        let name = url.lastPathComponent

        guard beginProcessing(url.path) else {
            print("[Archivist][Pipeline] \(name): already being processed (in flight) — skipping this trigger")
            return nil
        }
        defer { endProcessing(url.path) }

        print("[Archivist][Pipeline] processing \(name)")

        guard let hash = ContentHasher.hash(of: url) else {
            print("[Archivist][Pipeline] \(name): could not hash file (unreadable?) — stopping")
            return nil
        }
        if store.nodeExists(contentHash: hash) {
            print("[Archivist][Pipeline] \(name): content hash already indexed — duplicate, skipping")
            return nil // true duplicate, skipped per plan.md section 5 step 3
        }

        let excerpt = Extractor.extractText(from: url) ?? ""
        guard !excerpt.isEmpty else {
            print("[Archivist][Pipeline] \(name): extractor returned no text — stopping. " +
                  "Extractor only supports .pdf/.docx/.pptx/.txt/.md; anything else " +
                  "(images, zips, installers, etc.) is silently skipped, by design (plan.md section 2).")
            return nil
        }
        print("[Archivist][Pipeline] \(name): extracted \(excerpt.count) chars of text")

        let existingTags = Set(store.allNodes().flatMap { $0.tags }).sorted()
        print("[Archivist][Pipeline] \(name): calling AI provider to classify/summarize/tag…")
        let (understanding, providerUsed) = await router.understand(
            excerpt: excerpt, filename: name, existingTags: existingTags
        )
        print("[Archivist][Pipeline] \(name): understood via \(providerUsed) -> " +
              "category=\(understanding.category) confidence=\(understanding.confidence) tags=\(understanding.tags)")

        let embedding = await router.embed(text: excerpt) ?? []
        print("[Archivist][Pipeline] \(name): embedding vector length = \(embedding.count) " +
              "(0 means no embedding-capable provider was reachable)")

        let status: NodeStatus = understanding.confidence >= settings.confidenceThreshold
            ? .indexed
            : .pendingReview
        print("[Archivist][Pipeline] \(name): confidence \(understanding.confidence) vs threshold " +
              "\(settings.confidenceThreshold) -> status = \(status.rawValue)")

        let nodeId = store.insertNode(
            path: url.path, filename: name, understanding: understanding,
            providerUsed: providerUsed, extractedText: excerpt, embedding: embedding,
            contentHash: hash, status: status
        )
        guard let node = store.node(id: nodeId) else {
            print("[Archivist][Pipeline] \(name): insertNode succeeded but re-reading it back failed — this shouldn't happen")
            return nil
        }
        print("[Archivist][Pipeline] \(name): node #\(node.id) written to graph store")

        RelationshipBuilder.relate(node: node, in: store)

        guard status == .indexed else {
            print("[Archivist][Pipeline] \(name): left in pending_review — check the Review tab " +
                  "(not renamed or tagged; only indexed files are, per the confidence gate)")
            return node
        }

        // Backfill indexes pre-existing files without ever renaming/moving them —
        // plan.md Flow B, "a bulk, hard-to-reverse action shouldn't happen without an
        // explicit, separate ask." The live watcher path (isBackfill == false) is the
        // only one that renames.
        var finalNode = node
        var finalURL = url
        if !isBackfill {
            if let renamed = renameUsingSkill(node: node, understanding: understanding, at: url) {
                finalURL = renamed.url
                finalNode = renamed.node
            }
        } else {
            print("[Archivist][Pipeline] \(name): backfill — indexing only, not renaming")
        }

        if TagWriter.write(category: finalNode.category, tags: finalNode.tags, to: finalURL) {
            print("[Archivist][Pipeline] \(finalURL.lastPathComponent): wrote Finder tags " +
                  "\(Array(Set([finalNode.category] + finalNode.tags)))")
        }

        return finalNode
    }

    /// Applies skills/filename-nomenclature.md to a freshly-indexed file: assembles
    /// the name (Step 1) via FilenameNomenclature using the ownership/category/
    /// docType/title the understanding call produced (itself governed by that same
    /// skill file — see PromptBuilder), resolves collisions against the destination
    /// folder (Step 2), and actually performs the rename on disk + graph.
    private func renameUsingSkill(node: Node, understanding: FileUnderstanding, at url: URL) -> (url: URL, node: Node)? {
        let name = url.lastPathComponent
        let directory = url.deletingLastPathComponent()
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var existingFilenames = Set(siblings)
        existingFilenames.remove(name) // renaming to our own current name isn't a "collision"

        let input = FilenameNomenclature.Input(
            ownership: understanding.ownership, category: node.category, docType: understanding.docType,
            title: understanding.title, personName: settings.personName, fileExtension: url.pathExtension
        )
        let newName = FilenameNomenclature.filename(for: input, existingFilenames: existingFilenames)

        guard newName != name else {
            print("[Archivist][Pipeline] \(name): naming skill produced the same name — no rename needed")
            return nil
        }

        let newURL = directory.appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
        } catch {
            print("[Archivist][Pipeline] \(name): rename to \(newName) FAILED: \(error)")
            return nil
        }

        store.recordMove(nodeId: node.id, srcPath: url.path, dstPath: newURL.path, triggeredBy: "auto-rename")
        guard let updated = store.node(id: node.id) else { return nil }
        print("[Archivist][Pipeline] \(name): renamed -> \(newName)")
        return (newURL, updated)
    }

    /// Returns false (caller should bail) if `path` is already being processed.
    private func beginProcessing(_ path: String) -> Bool {
        inFlightLock.lock()
        defer { inFlightLock.unlock() }
        guard !inFlightPaths.contains(path) else { return false }
        inFlightPaths.insert(path)
        return true
    }

    private func endProcessing(_ path: String) {
        inFlightLock.lock()
        defer { inFlightLock.unlock() }
        inFlightPaths.remove(path)
    }

    /// Backfill (plan.md Flow B): index everything in `directory` not already
    /// indexed, in place, no moves.
    func backfill(directory: URL) async -> [Node] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [Node] = []
        for file in files {
            if let node = await process(fileAt: file, isBackfill: true) {
                results.append(node)
            }
        }
        return results
    }
}
