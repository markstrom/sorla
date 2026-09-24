import AppKit
import os

// None of Sorla's windows has a Cancel button, so Esc (and ⌘.) closes them like a dialog.
final class SorlaWindow: NSWindow {
    private static let logger = Logger(subsystem: "com.sorla.app", category: "SorlaWindow")
    private var activationObserver: NSObjectProtocol?

    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    // The one way Settings, About and Welcome come forward, from the status menu or at launch.
    func present(then didPresent: @escaping @MainActor (SorlaWindow) -> Void = { _ in }) {
        // Opened from the status menu: wait until it has closed, or macOS may leave the window behind others.
        DispatchQueue.main.async { [weak self] in
            self?.bringForward(then: didPresent)
        }
    }

    private func bringForward(then didPresent: @escaping @MainActor (SorlaWindow) -> Void) {
        // Opens on the Space in use, over a full-screen app too, instead of switching to the Space it was last on.
        collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary])
        if isMiniaturized {
            deminiaturize(nil)
        }
        stopWaitingForActivation()
        logState("show")
        orderFrontRegardless()
        guard !NSApp.isActive else {
            finish(didPresent)
            return
        }
        // Activation lands later; a window made key before then can end up behind the app that was in front.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stopWaitingForActivation()
                self.finish(didPresent)
            }
        }
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.activationObserver != nil else { return }
            self.logState("still waiting for activation")
        }
    }

    private func finish(_ didPresent: @MainActor (SorlaWindow) -> Void) {
        makeKeyAndOrderFront(nil)
        didPresent(self)
        logState("shown")
    }

    private func stopWaitingForActivation() {
        guard let activationObserver else { return }
        NotificationCenter.default.removeObserver(activationObserver)
        self.activationObserver = nil
    }

    // Window state only, never content, for reproducing a window that opened behind others (#39).
    private func logState(_ event: String) {
        let window = windowController.map { String(describing: type(of: $0)) } ?? "window"
        let isSorlaFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier
        Self.logger.info("\(window, privacy: .public) \(event, privacy: .public): active=\(NSApp.isActive, privacy: .public) frontmost=\(isSorlaFrontmost, privacy: .public) key=\(self.isKeyWindow, privacy: .public) visible=\(self.isVisible, privacy: .public) occluded=\(!self.occlusionState.contains(.visible), privacy: .public) miniaturized=\(self.isMiniaturized, privacy: .public) activeSpace=\(self.isOnActiveSpace, privacy: .public)")
    }
}
