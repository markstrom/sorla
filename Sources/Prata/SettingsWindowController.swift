import AppKit
import PrataCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onKeyStateChange: ((Bool) -> Void)?

    convenience init(appSettings: AppSettings, modelLoadingStatus: ModelLoadingStatus) {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Prata Settings"
        window.contentViewController = NSHostingController(
            rootView: SettingsView(appSettings: appSettings, modelLoadingStatus: modelLoadingStatus)
        )
        window.isReleasedWhenClosed = false
        window.center()

        self.init(window: window)
        window.delegate = self
    }

    func show() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
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
