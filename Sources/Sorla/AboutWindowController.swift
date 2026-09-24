import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    init() {
        let window = SorlaWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = String(localized: "About Sorla")
        window.contentViewController = NSHostingController(rootView: AboutView())
        window.isReleasedWhenClosed = false
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        (window as? SorlaWindow)?.present()
    }
}
