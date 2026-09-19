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
        let callback: FSEventStreamCallback = { _, clientInfo, numEvents, eventPaths, _, _ in
            guard let clientInfo else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
            // kFSEventStreamCreateFlagUseCFTypes means `eventPaths` IS the CFArrayRef
            // itself (an array of CFStrings), not a pointer to a C array of char*/
            // pointers — indexing into it as if it were the latter reads into the
            // CFArray object's own memory and crashes almost immediately.
            let cfPathsArray = unsafeBitCast(eventPaths, to: CFArray.self)
            for i in 0..<numEvents {
                guard let raw = CFArrayGetValueAtIndex(cfPathsArray, i) else { continue }
                let cfString = unsafeBitCast(raw, to: CFString.self)
                watcher.handleRawEvent(path: cfString as String)
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
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
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
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return
        }
        pendingPaths.insert(path)
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.flushPending()
        }
    }

    private func flushPending() {
        let paths = pendingPaths
        pendingPaths.removeAll()
        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            onNewFile(URL(fileURLWithPath: path))
        }
    }
}
