import Foundation

/// Orchestrates dedup -> extract -> understand -> embed -> graph write -> relate ->
/// Finder-tag write -> confidence branch, for one file. Shared by the live watcher
/// (Flow A) and the backfill command (Flow B) — plan.md section 5.
final class Pipeline {
    let store: GraphStore
    let router: ProviderRouter
    let settings: SettingsStore

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

        if status == .indexed {
            TagWriter.write(category: node.category, tags: node.tags, to: url)
            print("[Archivist][Pipeline] \(name): wrote Finder tags \([node.category] + node.tags)")
        } else {
            print("[Archivist][Pipeline] \(name): left in pending_review — check the Review tab")
        }

        return node
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
