import AppKit
import PrataCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init(appSettings: AppSettings) {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Prata Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView(appSettings: appSettings))
        window.isReleasedWhenClosed = false
        window.center()

        self.init(window: window)
    }

    func show() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
