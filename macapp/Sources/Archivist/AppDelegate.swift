import AppKit
import SwiftUI

/// Menu bar shell: NSStatusItem in the top toolbar, no Dock icon (.accessory),
/// clicking opens a popover hosting ContentView — plan.md section 2/6.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[Archivist][AppDelegate] applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)

        let statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusBarItem.button {
            button.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: "Archivist")
            button.action = #selector(togglePopover)
            button.target = self
            print("[Archivist][AppDelegate] menu bar status item created")
        } else {
            print("[Archivist][AppDelegate] WARNING: statusBarItem.button was nil — no menu bar icon will show")
        }
        self.statusItem = statusBarItem

        let contentView = ContentView(environment: environment)
        let hostingController = NSHostingController(rootView: contentView)
        // Fixed size set explicitly (matching ContentView.size) before the popover
        // is ever shown — see the comment on ContentView for why leaving this to
        // SwiftUI's automatic sizing let the window drift off the top of the screen.
        hostingController.preferredContentSize = ContentView.size
        let popover = NSPopover()
        popover.contentViewController = hostingController
        popover.contentSize = ContentView.size
        popover.behavior = .transient
        self.popover = popover

        environment.startWatching()
        print("[Archivist][AppDelegate] launch sequence complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.stopWatching()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
