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

    // Opened from the status menu: wait until it has closed, or macOS may leave the window behind others.
    func show() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            window.orderFrontRegardless()
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }
}
