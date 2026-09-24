import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    private let updateRequest = UpdateCheckRequest()

    init() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = String(localized: "About Sorla")
        window.contentViewController = NSHostingController(rootView: AboutView(updateRequest: updateRequest))
        window.isReleasedWhenClosed = false
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
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

    func showAndCheckForUpdates() {
        updateRequest.isPending = true
        show()
    }
}
