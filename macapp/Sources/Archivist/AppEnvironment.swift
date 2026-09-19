import Foundation

/// Wires up the singletons the whole app shares: one GraphStore file, one
/// SettingsStore, one ProviderRouter built from it, and the Pipeline/CommandInterpreter
/// that use them. Created once at launch (see main.swift).
final class AppEnvironment: ObservableObject {
    let settings: SettingsStore
    let store: GraphStore
    let router: ProviderRouter
    let pipeline: Pipeline
    let commandInterpreter: CommandInterpreter
    private var watcher: FileWatcher?

    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Archivist", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        self.settings = SettingsStore()
        self.store = GraphStore(path: Self.supportDirectory.appendingPathComponent("graph.sqlite3").path)
        self.router = ProviderRouter(settings: settings)
        self.pipeline = Pipeline(store: store, router: router, settings: settings)
        self.commandInterpreter = CommandInterpreter(router: router, store: store)
    }

    /// Starts the always-on Downloads (and optionally Desktop) watcher — plan.md
    /// section 6, "the only always-running piece."
    func startWatching() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths = [home.appendingPathComponent("Downloads").path]
        if settings.watchDesktopToo {
            paths.append(home.appendingPathComponent("Desktop").path)
        }
        watcher = FileWatcher(paths: paths) { [weak self] url in
            Task { await self?.pipeline.process(fileAt: url) }
        }
        watcher?.start()
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }
}
