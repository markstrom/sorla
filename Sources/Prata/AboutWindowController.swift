import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Prata"
        window.contentViewController = NSHostingController(rootView: AboutView())
        window.isReleasedWhenClosed = false
        window.center()

        self.init(window: window)
    }

    func show() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
