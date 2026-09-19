import Foundation

/// Processes watched files strictly one at a time, FIFO.
///
/// Without this, each detected file spawned its own independent Task, so two files
/// landing within the same few minutes (very plausible: the AI call alone takes
/// 1-3+ minutes with local Ollama) could both fetch `existingTags` from the graph
/// before either had finished inserting — the second file would have no visibility
/// into the first's just-chosen tags, undermining skills/tagging.md's "check
/// existing tags first" requirement in practice even though the code path does
/// query the database correctly. Serializing guarantees that by the time any file's
/// existingTags snapshot is taken, every previously-detected file has fully
/// finished (including its DB insert), so genuinely similar content downloaded
/// close together reliably sees and can reuse each other's tags.
actor ProcessingQueue {
    private let pipeline: Pipeline
    private var pending: [URL] = []
    private var isDraining = false

    init(pipeline: Pipeline) {
        self.pipeline = pipeline
    }

    func enqueue(_ url: URL) {
        pending.append(url)
        guard !isDraining else { return }
        isDraining = true
        Task { await drain() }
    }

    private func drain() async {
        while !pending.isEmpty {
            let next = pending.removeFirst()
            print("[Archivist][ProcessingQueue] starting \(next.lastPathComponent) (\(pending.count) more queued)")
            let node = await pipeline.process(fileAt: next)
            if let node {
                print("[Archivist][ProcessingQueue] finished \(next.lastPathComponent) -> " +
                      "status=\(node.status.rawValue) category=\(node.category) confidence=\(node.confidence)")
            } else {
                print("[Archivist][ProcessingQueue] \(next.lastPathComponent) produced no node " +
                      "(pre-existing file, duplicate, empty extraction, or unsupported type — see Pipeline logs above)")
            }
        }
        isDraining = false
    }
}
