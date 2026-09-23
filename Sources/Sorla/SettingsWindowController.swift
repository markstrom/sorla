import AppKit
import SorlaCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onKeyStateChange: ((Bool) -> Void)?

    convenience init(appSettings: AppSettings, modelManager: ModelManager) {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = SettingsView.windowTitle
        window.contentViewController = NSHostingController(
            rootView: SettingsView(appSettings: appSettings, modelManager: modelManager)
        )
        window.isReleasedWhenClosed = false
        window.center()

        self.init(window: window)
        window.delegate = self
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

    func windowDidBecomeKey(_ notification: Notification) {
        onKeyStateChange?(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        onKeyStateChange?(false)
    }

    func windowWillClose(_ notification: Notification) {
        onKeyStateChange?(false)
    }
}
