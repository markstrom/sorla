import AppKit
import KeyboardShortcuts
import os

public extension KeyboardShortcuts.Name {
    static let sorlaCustomTrigger = Self("sorlaCustomTrigger")
    static let pasteLastTranscription = Self("pasteLastTranscription", initial: .init(.v, modifiers: [.control, .option]))
}

public enum TriggerEdge: Equatable, Sendable {
    case down
    case up

    // Sorla's own ⌘V can arrive as modifier changes, so a release only counts once the key is physically up.
    public static func forModifierEvent(
        isSynthetic: Bool,
        hasTriggerFlag: Bool,
        isKeyPhysicallyDown: () -> Bool
    ) -> TriggerEdge? {
        guard !isSynthetic else { return nil }
        if hasTriggerFlag { return .down }
        return isKeyPhysicallyDown() ? nil : .up
    }

    public static let releaseRecheckDelay: Duration = .milliseconds(100)

    // The key state can be stale (Fn/Globe, remapping tools), so an ignored release gets one more look while a press is in progress.
    public static func shouldRecheckRelease(isSynthetic: Bool, hasTriggerFlag: Bool, isWaitingForRelease: Bool) -> Bool {
        !isSynthetic && !hasTriggerFlag && isWaitingForRelease
    }

    public static func afterRecheck(isKeyPhysicallyDown: Bool) -> TriggerEdge? {
        isKeyPhysicallyDown ? nil : .up
    }
}

@MainActor
public final class TriggerMonitor {
    private static let logger = Logger(subsystem: "com.sorla.app", category: "TriggerMonitor")
    private var gesture = PushToTalkGesture()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isCustomShortcutActive = false
    private var isRecordingActive = false
    private var releaseRecheck: Task<Void, Never>?

    public var isSuspended = false {
        didSet {
            guard isSuspended, isSuspended != oldValue else { return }
            releaseRecheck?.cancel()
            if isRecordingActive {
                isRecordingActive = false
                onCancel()
            }
            gesture.reset()
        }
    }

    private let onStart: () -> Bool
    private let onFinish: () -> Void
    private let onCancel: () -> Void

    public init(
        onStart: @escaping @MainActor () -> Bool,
        onFinish: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.onStart = onStart
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        // Safe: this instance is only ever touched and released from the main actor.
        if isCustomShortcutActive {
            MainActor.assumeIsolated {
                KeyboardShortcuts.removeHandler(for: .sorlaCustomTrigger)
            }
        }
    }

    public func configure(trigger: TriggerKey, mode: RecordingMode) {
        if isRecordingActive {
            isRecordingActive = false
            onCancel()
        }

        tearDown()
        gesture = PushToTalkGesture(mode: mode)

        switch trigger {
        case .customShortcut:
            setUpCustomShortcut()
        case .rightCommand, .rightOption, .rightControl, .fn:
            setUpModifierMonitor(for: trigger)
        }
    }

    private func tearDown() {
        releaseRecheck?.cancel()
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if isCustomShortcutActive {
            KeyboardShortcuts.removeHandler(for: .sorlaCustomTrigger)
            isCustomShortcutActive = false
        }
    }

    private func setUpModifierMonitor(for trigger: TriggerKey) {
        guard let keyCode = trigger.keyCode, let deviceMask = trigger.deviceMask else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleModifierEvent(event, keyCode: keyCode, deviceMask: deviceMask)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleModifierEvent(event, keyCode: keyCode, deviceMask: deviceMask)
            }
            return event
        }
    }

    // KeyboardShortcuts only reports down/up of the registered combo, so there's no "other key while held" signal here.
    private func setUpCustomShortcut() {
        isCustomShortcutActive = true

        KeyboardShortcuts.onKeyDown(for: .sorlaCustomTrigger) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isSuspended else { return }
                self.dispatch(self.gesture.handle(.triggerDown(at: ProcessInfo.processInfo.systemUptime)))
            }
        }

        KeyboardShortcuts.onKeyUp(for: .sorlaCustomTrigger) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isSuspended else { return }
                self.dispatch(self.gesture.handle(.triggerUp(at: ProcessInfo.processInfo.systemUptime)))
            }
        }
    }

    private func handleModifierEvent(_ event: NSEvent, keyCode: UInt16, deviceMask: UInt) {
        guard !isSuspended else { return }
        let action: PushToTalkGesture.Action?

        switch event.type {
        case .flagsChanged:
            guard event.keyCode == keyCode else { return }
            releaseRecheck?.cancel()
            let isSynthetic = Self.isSorlaSyntheticEvent(event)
            let hasTriggerFlag = event.modifierFlags.rawValue & deviceMask != 0
            let edge = TriggerEdge.forModifierEvent(
                isSynthetic: isSynthetic,
                hasTriggerFlag: hasTriggerFlag,
                isKeyPhysicallyDown: { CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keyCode)) }
            )
            switch edge {
            case .down:
                action = gesture.handle(.triggerDown(at: event.timestamp))
            case .up:
                action = gesture.handle(.triggerUp(at: event.timestamp))
            case nil:
                Self.logger.info("trigger flagsChanged ignored: synthetic=\(isSynthetic, privacy: .public) flag=\(hasTriggerFlag, privacy: .public)")
                if TriggerEdge.shouldRecheckRelease(
                    isSynthetic: isSynthetic,
                    hasTriggerFlag: hasTriggerFlag,
                    isWaitingForRelease: gesture.isWaitingForRelease
                ) {
                    scheduleReleaseRecheck(keyCode: keyCode)
                }
                return
            }
        case .keyDown:
            guard !Self.isSorlaSyntheticEvent(event) else { return }
            action = gesture.handle(.otherKeyDown)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            action = gesture.handle(.otherKeyDown)
        default:
            return
        }

        dispatch(action)
    }

    private func scheduleReleaseRecheck(keyCode: UInt16) {
        releaseRecheck = Task { @MainActor [weak self] in
            try? await Task.sleep(for: TriggerEdge.releaseRecheckDelay)
            guard let self, !Task.isCancelled, !self.isSuspended, self.gesture.isWaitingForRelease else { return }
            let isDown = CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keyCode))
            guard TriggerEdge.afterRecheck(isKeyPhysicallyDown: isDown) == .up else { return }
            Self.logger.info("trigger release confirmed on recheck")
            self.dispatch(self.gesture.handle(.triggerUp(at: ProcessInfo.processInfo.systemUptime)))
        }
    }

    // Sorla's own ⌘V paste posts events this monitor would otherwise read as another key or a trigger release.
    private static func isSorlaSyntheticEvent(_ event: NSEvent) -> Bool {
        guard let marker = event.cgEvent?.getIntegerValueField(.eventSourceUserData) else { return false }
        return PasteService.isSyntheticMarker(marker)
    }

    private func dispatch(_ action: PushToTalkGesture.Action?) {
        switch action {
        case .start:
            if onStart() {
                isRecordingActive = true
            } else {
                isRecordingActive = false
                gesture.reset()
            }
        case .finish:
            isRecordingActive = false
            onFinish()
        case .cancel:
            isRecordingActive = false
            onCancel()
        case nil:
            break
        }
    }
}
