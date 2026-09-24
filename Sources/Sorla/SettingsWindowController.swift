import AppKit
import SorlaCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onKeyStateChange: ((Bool) -> Void)?
    private var navigation: SettingsNavigation?

    convenience init(appSettings: AppSettings, modelManager: ModelManager, updateChecker: UpdateChecker, appUpdater: AppUpdater, announce: @escaping (String) -> Void) {
        let navigation = SettingsNavigation()
        let window = Self.makeWindow(content: NSHostingController(
            rootView: SettingsView(
                appSettings: appSettings,
                modelManager: modelManager,
                updateChecker: updateChecker,
                appUpdater: appUpdater,
                navigation: navigation,
                announce: announce
            )
        ))

        self.init(window: window)
        self.navigation = navigation
        window.delegate = self
    }

    func revealUpdates() {
        navigation?.showsUpdates = true
    }

    static func makeWindow(content: NSViewController) -> SorlaWindow {
        let window = SorlaWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = SettingsView.windowTitle
        window.contentViewController = content
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    func show() {
        (window as? SorlaWindow)?.present { window in
            Self.clearInitialFocus(of: window)
        }
    }

    // A focused shortcut field would swallow the first Esc (#36); SwiftUI focuses a turn later, so clear it then too.
    static func clearInitialFocus(
        of window: NSWindow,
        nextTurn: (@escaping @MainActor () -> Void) -> Void = { work in DispatchQueue.main.async { work() } }
    ) {
        window.makeFirstResponder(nil)
        nextTurn { window.makeFirstResponder(nil) }
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
