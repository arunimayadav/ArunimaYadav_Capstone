import Foundation

/// A proposed reorganization action, shown to the user for confirmation before
/// anything on disk changes — plan.md section 6/8 ("always propose before they act").
struct ProposedAction {
    var destinationFolderName: String
    var matchedNodes: [Node]
}

enum CommandInterpreterError: Error {
    case noMatches
}

final class CommandInterpreter {
    private let router: ProviderRouter
    private let store: GraphStore

    init(router: ProviderRouter, store: GraphStore) {
        self.router = router
        self.store = store
    }

    /// "create a folder for anything related to my bank and put those files in it"
    /// -> parsed intent -> graph search -> a proposal the user must confirm.
    func propose(for instruction: String) async throws -> ProposedAction {
        let parsed = try await router.interpretCommand(instruction)
        let matches = store.search(query: parsed.searchQuery)
        guard !matches.isEmpty else { throw CommandInterpreterError.noMatches }
        return ProposedAction(destinationFolderName: parsed.destinationFolderName, matchedNodes: matches)
    }

    /// Executes a confirmed proposal: create the folder, move each matched file,
    /// log every move (plan.md section 7 `moves` table).
    func execute(_ action: ProposedAction, into parentDirectory: URL) throws -> [MoveRecord] {
        let destination = parentDirectory.appendingPathComponent(action.destinationFolderName)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        var moved: [MoveRecord] = []
        for node in action.matchedNodes {
            let source = URL(fileURLWithPath: node.path)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }

            var target = destination.appendingPathComponent(source.lastPathComponent)
            target = uniqueDestination(for: target)

            try FileManager.default.moveItem(at: source, to: target)
            let moveId = store.recordMove(nodeId: node.id, srcPath: source.path, dstPath: target.path, triggeredBy: "command")
            moved.append(MoveRecord(id: moveId, nodeId: node.id, srcPath: source.path, dstPath: target.path,
                                     timestamp: Date(), triggeredBy: "command", reversed: false))
        }
        return moved
    }

    /// Never overwrite an existing file at the destination — append a disambiguating
    /// suffix instead (plan.md section 7 edge cases).
    private func uniqueDestination(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let directory = url.deletingLastPathComponent()
        var counter = 2
        var candidate = url
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }
}
