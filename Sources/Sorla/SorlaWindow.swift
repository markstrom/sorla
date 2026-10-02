import AppKit
import os

// None of Sorla's windows has a Cancel button, so Esc (and ⌘.) closes them like a dialog.
final class SorlaWindow: NSWindow {
    private static let logger = Logger(subsystem: "com.sorla.app", category: "SorlaWindow")
    // One for all of Sorla's windows, so only the newest request may raise one (#86).
    private static var presentation = WindowPresentation()
    static let activationRetryDelay: TimeInterval = 0.25

    // This window's request while it waits for its turn or for Sorla's activation.
    private var request: Int?
    // The app in front when the window was asked for: the one the status menu was opened from, which gets the focus
    // back while the menu closes. Any other app coming forward means the user has moved on.
    private var sourceProcessID: pid_t?
    private var activationObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        // Opens on the Space in use, over a full-screen app too, instead of switching to the Space it was last on.
        collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary])
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    // A later activation, say for another Sorla window, must not bring this one back.
    override func close() {
        endPresentation(request)
        super.close()
    }

    // The one way Settings, About, Welcome and the recovery windows come forward, from the status menu or at launch.
    func present(then didPresent: @escaping @MainActor (SorlaWindow) -> Void = { _ in }) {
        endPresentation(request)
        let request = Self.presentation.request()
        self.request = request
        sourceProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Self.afterMenuTracking { [weak self] in
            self?.bringForward(request, then: didPresent)
        }
    }

    // DispatchQueue.main also runs while the status menu is still tracking, before it has handed the focus back to the
    // app it was opened from, which then ends up in front of the window. The default run loop mode only comes back
    // once the menu has closed (#86).
    static func afterMenuTracking(_ work: @escaping @MainActor () -> Void) {
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                work()
            }
        }
    }

    private func bringForward(_ request: Int, then didPresent: @escaping @MainActor (SorlaWindow) -> Void) {
        // Closed, or asked for again, before its turn.
        guard self.request == request else {
            logState("not shown (closed before its turn)")
            return
        }
        if isMiniaturized {
            deminiaturize(nil)
        }
        // Another window was asked for since, or the user went on to another app: shown, but without taking the focus.
        guard Self.presentation.isCurrent(request), !hasSwitchedToAnotherApp else {
            endPresentation(request)
            orderFront(nil)
            logState("shown without the focus (superseded, or another app came forward)")
            return
        }
        // Registered before ordering or activating, since either can make Sorla active at once.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.request == request, Self.presentation.appDidBecomeActive(request) else { return }
                self.finish(request, then: didPresent)
            }
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.request == request, self.hasSwitchedToAnotherApp else { return }
                self.logState("not made key (another app came forward)")
                self.endPresentation(request)
            }
        }
        logState("show")
        switch Self.presentation.bringForward(request, isAppActive: NSApp.isActive) {
        case .show:
            finish(request, then: didPresent)
        case .waitForActivation:
            orderFrontRegardless()
            // Ordering it in may already have made Sorla active, and the observer has finished it.
            guard self.request == request else { return }
            NSApp.activate()
            checkActivation(request, then: didPresent)
        case .none:
            endPresentation(request)
        }
    }

    // Activation can be declined, or land without a notification. A few short retries, then the request expires and its
    // observers go, so a later activation for something else never raises this window.
    private func checkActivation(_ request: Int, then didPresent: @escaping @MainActor (SorlaWindow) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationRetryDelay) { [weak self] in
            guard let self, self.request == request else { return }
            switch Self.presentation.retry(request, isAppActive: NSApp.isActive, hasSwitchedApp: self.hasSwitchedToAnotherApp) {
            case .show:
                self.finish(request, then: didPresent)
            case .waitForActivation:
                NSApp.activate()
                self.checkActivation(request, then: didPresent)
            case .none:
                self.logState("not made key (activation didn't come)")
                self.endPresentation(request)
            }
        }
    }

    // Coming back to the app the menu was opened from is part of the menu closing; any other app is the user moving on.
    private var hasSwitchedToAnotherApp: Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        return frontmost != NSRunningApplication.current.processIdentifier && frontmost != sourceProcessID
    }

    private func finish(_ request: Int, then didPresent: @MainActor (SorlaWindow) -> Void) {
        let mayTakeFocus = Self.presentation.isCurrent(request) && !hasSwitchedToAnotherApp
        endPresentation(request)
        guard mayTakeFocus else { return }
        makeKeyAndOrderFront(nil)
        didPresent(self)
        logState("shown")
    }

    // Only this window's own request, so a stale callback can't end a newer one.
    private func endPresentation(_ request: Int?) {
        guard let request, self.request == request else { return }
        Self.presentation.end(request)
        self.request = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
    }

    // Window state only, never content, for reproducing a window that opened behind others (#39).
    private func logState(_ event: String) {
        let window = windowController.map { String(describing: type(of: $0)) } ?? "window"
        let isSorlaFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier
        Self.logger.info("\(window, privacy: .public) \(event, privacy: .public): active=\(NSApp.isActive, privacy: .public) frontmost=\(isSorlaFrontmost, privacy: .public) key=\(self.isKeyWindow, privacy: .public) visible=\(self.isVisible, privacy: .public) occluded=\(!self.occlusionState.contains(.visible), privacy: .public) miniaturized=\(self.isMiniaturized, privacy: .public) activeSpace=\(self.isOnActiveSpace, privacy: .public)")
    }
}

// Which request, if any, may still raise a window when its turn or Sorla's activation comes (#39, #86). Shared by all
// of Sorla's windows: a newer request supersedes an older one, and every step names the request it belongs to.
struct WindowPresentation: Equatable {
    enum Step: Equatable {
        case none
        case show
        case waitForActivation
    }

    // About a second at SorlaWindow.activationRetryDelay; an activation that hasn't come by then was declined.
    static let maximumRetries = 4

    private(set) var current: Int?
    private(set) var isWaitingForActivation = false
    private var lastRequest = 0
    private var retries = 0

    mutating func request() -> Int {
        lastRequest += 1
        current = lastRequest
        isWaitingForActivation = false
        retries = 0
        return lastRequest
    }

    func isCurrent(_ request: Int) -> Bool {
        current == request
    }

    mutating func bringForward(_ request: Int, isAppActive: Bool) -> Step {
        guard isCurrent(request) else { return .none }
        isWaitingForActivation = !isAppActive
        return isAppActive ? .show : .waitForActivation
    }

    // Returns whether to make the window key now that Sorla is active.
    mutating func appDidBecomeActive(_ request: Int) -> Bool {
        guard isCurrent(request), isWaitingForActivation else { return false }
        isWaitingForActivation = false
        return true
    }

    // Checked shortly after asking to be activated: finish if Sorla is active, ask again a few times, then give up.
    // The user moving on to another app ends it at once, even if Sorla became active meanwhile.
    mutating func retry(_ request: Int, isAppActive: Bool, hasSwitchedApp: Bool) -> Step {
        guard isCurrent(request), isWaitingForActivation else { return .none }
        if hasSwitchedApp {
            end(request)
            return .none
        }
        if isAppActive {
            isWaitingForActivation = false
            return .show
        }
        guard retries < Self.maximumRetries else {
            end(request)
            return .none
        }
        retries += 1
        return .waitForActivation
    }

    // Closed, shown or given up; an older request's cleanup leaves a newer one alone.
    mutating func end(_ request: Int) {
        guard isCurrent(request) else { return }
        current = nil
        isWaitingForActivation = false
    }
}
