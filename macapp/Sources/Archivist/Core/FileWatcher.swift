import Foundation
import CoreServices

/// FSEvents-based watcher on Downloads (and optionally Desktop) — plan.md section 6.
/// Debounces by waiting for a short quiet period after the last event for a given
/// path before firing, since a "file created" event can fire while the write is
/// still in progress (e.g. a browser download still streaming to disk).
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let onNewFile: (URL) -> Void
    private var pendingPaths: Set<String> = []
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 2.0

    init(paths: [String], onNewFile: @escaping (URL) -> Void) {
        self.paths = paths
        self.onNewFile = onNewFile
    }

    func start() {
        print("[Archivist][FileWatcher] start() called for paths: \(paths)")

        let callback: FSEventStreamCallback = { _, clientInfo, numEvents, eventPaths, _, _ in
            guard let clientInfo else {
                print("[Archivist][FileWatcher] callback fired with nil clientInfo — dropping event")
                return
            }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
            print("[Archivist][FileWatcher] callback fired with \(numEvents) raw event(s)")
            // kFSEventStreamCreateFlagUseCFTypes means `eventPaths` IS the CFArrayRef
            // itself (an array of CFStrings), not a pointer to a C array of char*/
            // pointers — indexing into it as if it were the latter reads into the
            // CFArray object's own memory and crashes almost immediately.
            let cfPathsArray = unsafeBitCast(eventPaths, to: CFArray.self)
            for i in 0..<numEvents {
                guard let raw = CFArrayGetValueAtIndex(cfPathsArray, i) else { continue }
                let cfString = unsafeBitCast(raw, to: CFString.self)
                let path = cfString as String
                print("[Archivist][FileWatcher] raw event path: \(path)")
                watcher.handleRawEvent(path: path)
            }
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        guard let stream else {
            print("[Archivist][FileWatcher] FSEventStreamCreate returned nil — stream was NOT created. " +
                  "Watching will not happen at all. Check that `paths` are valid, existing directories.")
            return
        }
        print("[Archivist][FileWatcher] FSEventStreamCreate succeeded")

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)

        let started = FSEventStreamStart(stream)
        if started {
            print("[Archivist][FileWatcher] FSEventStreamStart succeeded — actively watching now")
        } else {
            print("[Archivist][FileWatcher] FSEventStreamStart returned FALSE — the stream did " +
                  "not start. This is the most likely explanation for 'nothing happens on download': " +
                  "no events will ever be delivered.")
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handleRawEvent(path: String) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            print("[Archivist][FileWatcher] ignoring event for path that no longer exists: \(path)")
            return
        }
        guard !isDirectory.boolValue else {
            print("[Archivist][FileWatcher] ignoring event for directory: \(path)")
            return
        }
        print("[Archivist][FileWatcher] queuing \(path) — will fire in \(debounceInterval)s if no more writes to it")
        pendingPaths.insert(path)
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.flushPending()
        }
    }

    private func flushPending() {
        let paths = pendingPaths
        pendingPaths.removeAll()
        print("[Archivist][FileWatcher] debounce elapsed — flushing \(paths.count) pending path(s): \(paths)")
        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else {
                print("[Archivist][FileWatcher] skipping \(path) — gone by the time debounce fired")
                continue
            }
            print("[Archivist][FileWatcher] handing off to pipeline: \(path)")
            onNewFile(URL(fileURLWithPath: path))
        }
    }
}
