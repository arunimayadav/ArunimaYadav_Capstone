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
        guard let hash = ContentHasher.hash(of: url) else { return nil }
        if store.nodeExists(contentHash: hash) {
            return nil // true duplicate, skipped per plan.md section 5 step 3
        }

        let excerpt = Extractor.extractText(from: url) ?? ""
        guard !excerpt.isEmpty else { return nil }

        let existingTags = Set(store.allNodes().flatMap { $0.tags }).sorted()
        let (understanding, providerUsed) = await router.understand(
            excerpt: excerpt, filename: url.lastPathComponent, existingTags: existingTags
        )
        let embedding = await router.embed(text: excerpt) ?? []

        let status: NodeStatus = understanding.confidence >= settings.confidenceThreshold
            ? .indexed
            : .pendingReview

        let nodeId = store.insertNode(
            path: url.path, filename: url.lastPathComponent, understanding: understanding,
            providerUsed: providerUsed, extractedText: excerpt, embedding: embedding,
            contentHash: hash, status: status
        )
        guard let node = store.node(id: nodeId) else { return nil }

        RelationshipBuilder.relate(node: node, in: store)

        if status == .indexed {
            TagWriter.write(category: node.category, tags: node.tags, to: url)
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
