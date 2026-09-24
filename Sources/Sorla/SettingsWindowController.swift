import AppKit
import SorlaCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onKeyStateChange: ((Bool) -> Void)?
    private var navigation: SettingsNavigation?

    convenience init(appSettings: AppSettings, modelManager: ModelManager, updateChecker: UpdateChecker, announce: @escaping (String) -> Void) {
        let navigation = SettingsNavigation()
        let window = SorlaWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = SettingsView.windowTitle
        window.contentViewController = NSHostingController(
            rootView: SettingsView(appSettings: appSettings, modelManager: modelManager, updateChecker: updateChecker, navigation: navigation, announce: announce)
        )
        window.isReleasedWhenClosed = false
        window.center()

        self.init(window: window)
        self.navigation = navigation
        window.delegate = self
    }

    func revealUpdates() {
        navigation?.showsUpdates = true
    }

    func show() {
        (window as? SorlaWindow)?.present { window in
            // A focused shortcut field would swallow the first Esc and could record the next key press.
            window.makeFirstResponder(nil)
            DispatchQueue.main.async { window.makeFirstResponder(nil) }
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
