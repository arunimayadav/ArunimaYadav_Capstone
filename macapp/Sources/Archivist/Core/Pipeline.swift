import Foundation

/// Orchestrates dedup -> extract -> understand -> embed -> graph write -> relate ->
/// rename -> Finder-tag write -> confidence branch, for one file freshly detected by
/// the live watcher. By explicit product decision, this only ever runs for newly
/// downloaded files — there is no backfill/bulk-index-existing-files path.
final class Pipeline {
    let store: GraphStore
    let router: ProviderRouter
    let settings: SettingsStore

    // Explicit product requirement: only files downloaded *after* the app starts
    // watching are ever processed — anything already sitting in Downloads must be
    // ignored entirely, not just left un-renamed. FSEvents is created with "since
    // now" semantics (see FileWatcher), which should already exclude pre-existing
    // files on its own — but in practice, something (Spotlight reindexing, iCloud/
    // sync software touching metadata, or another process writing to an old file)
    // can still generate an event for a file that long predates the watcher. Rather
    // than trust FSEvents' timing alone, this checks the file's actual creation date
    // against when watching started, as a hard, independent guarantee.
    private(set) var watchStartTime: Date?

    init(store: GraphStore, router: ProviderRouter, settings: SettingsStore) {
        self.store = store
        self.router = router
        self.settings = settings
    }

    func markWatchStarted() {
        watchStartTime = Date()
        print("[Archivist][Pipeline] watch start time recorded: \(watchStartTime!) — " +
              "files created before this are pre-existing and will be ignored")
    }

    /// Callers must serialize invocations (see ProcessingQueue) — processing two
    /// files concurrently would let a later file's `existingTags` snapshot miss an
    /// earlier file's just-chosen tags, since the AI call alone can take minutes.
    @discardableResult
    func process(fileAt url: URL) async -> Node? {
        let name = url.lastPathComponent
        print("[Archivist][Pipeline] processing \(name)")

        guard let watchStartTime else {
            print("[Archivist][Pipeline] \(name): watcher hasn't recorded a start time — ignoring to be safe")
            return nil
        }
        guard let createdAt = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate else {
            print("[Archivist][Pipeline] \(name): could not read creation date — ignoring to be safe " +
                  "(only files created after the watcher started should ever be processed)")
            return nil
        }
        guard createdAt >= watchStartTime else {
            print("[Archivist][Pipeline] \(name): created \(createdAt), before watch start \(watchStartTime) " +
                  "— pre-existing file, ignoring entirely")
            return nil
        }

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

        // A file can be deleted or moved away out-of-band (by the user, by another
        // app, or as a duplicate cleanup) in the minutes between insertion and this
        // point — the AI call alone can take that long. Catching it here, before
        // even attempting the rename, avoids leaving a permanently un-renamed,
        // confusing "stuck with its original ugly name" record sitting in the graph
        // forever with no path forward to fix itself.
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[Archivist][Pipeline] \(name): source file no longer exists — it was likely deleted " +
                  "or moved away while this was being processed. Removing this now-stale entry rather " +
                  "than leaving it stuck with its pre-rename name.")
            store.deleteNode(id: node.id)
            return nil
        }

        var finalNode = node
        var finalURL = url
        if let renamed = renameUsingSkill(node: node, understanding: understanding, at: url) {
            finalURL = renamed.url
            finalNode = renamed.node
        } else if store.node(id: node.id) == nil {
            // renameUsingSkill deleted the node itself (source vanished mid-move).
            print("[Archivist][Pipeline] \(name): node was removed during the rename attempt — nothing to return")
            return nil
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
            if !FileManager.default.fileExists(atPath: url.path) {
                // Vanished in the narrow window between Pipeline's own existence
                // check and this move actually running — same cleanup as that check.
                print("[Archivist][Pipeline] \(name): rename failed because the source vanished " +
                      "mid-move — removing this now-stale entry: \(error)")
                store.deleteNode(id: node.id)
            } else {
                print("[Archivist][Pipeline] \(name): rename to \(newName) FAILED: \(error)")
            }
            return nil
        }

        store.recordMove(nodeId: node.id, srcPath: url.path, dstPath: newURL.path, triggeredBy: "auto-rename")
        guard let updated = store.node(id: node.id) else { return nil }
        print("[Archivist][Pipeline] \(name): renamed -> \(newName)")
        return (newURL, updated)
    }
}
