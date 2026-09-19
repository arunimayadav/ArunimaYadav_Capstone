import AppKit

// Unbuffered stdout so [Archivist] debug prints show up immediately in the
// terminal, rather than sitting in a buffer until the process exits cleanly
// (a GUI app killed via signal, e.g. Cmd+Q or a crash, may never flush otherwise).
setbuf(stdout, nil)

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
