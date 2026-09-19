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
    private let processingQueue: ProcessingQueue
    private var watcher: FileWatcher?

    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Archivist", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        print("[Archivist][AppEnvironment] init — support dir: \(Self.supportDirectory.path)")
        self.settings = SettingsStore()
        self.store = GraphStore(path: Self.supportDirectory.appendingPathComponent("graph.sqlite3").path)
        self.router = ProviderRouter(settings: settings)
        self.pipeline = Pipeline(store: store, router: router, settings: settings)
        self.commandInterpreter = CommandInterpreter(router: router, store: store)
        self.processingQueue = ProcessingQueue(pipeline: pipeline)
    }

    /// Starts the always-on Downloads (and optionally Desktop) watcher — plan.md
    /// section 6, "the only always-running piece."
    func startWatching() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths = [home.appendingPathComponent("Downloads").path]
        if settings.watchDesktopToo {
            paths.append(home.appendingPathComponent("Desktop").path)
        }
        print("[Archivist][AppEnvironment] startWatching() — will watch: \(paths)")

        // FSEvents fails *silently* (no crash, no events, no error) if this process
        // hasn't been granted access to these folders — probing with a plain
        // directory listing surfaces that immediately, since a denied read throws
        // here whereas a denied FSEvents subscription just never fires anything.
        for path in paths {
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: path)
                print("[Archivist][AppEnvironment] read-access check OK for \(path) — \(contents.count) entr(y/ies) visible")
            } catch {
                print("[Archivist][AppEnvironment] read-access check FAILED for \(path): \(error). " +
                      "This almost certainly means macOS hasn't granted this process permission to " +
                      "that folder — check System Settings > Privacy & Security > Files and Folders " +
                      "(look for Terminal/VSCode/whatever launched `swift run`, since that's the process " +
                      "identity TCC attributes this access to, not 'Archivist' itself).")
            }
        }

        pipeline.markWatchStarted()

        watcher = FileWatcher(paths: paths) { [weak self] url in
            print("[Archivist][AppEnvironment] watcher reported new file: \(url.path) — enqueuing")
            Task { await self?.processingQueue.enqueue(url) }
        }
        watcher?.start()
    }

    func stopWatching() {
        print("[Archivist][AppEnvironment] stopWatching()")
        watcher?.stop()
        watcher = nil
    }
}
