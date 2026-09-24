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
        isWaitingForRelease: Bool = false,
        trustsKeyState: Bool = true,
        isKeyPhysicallyDown: () -> Bool
    ) -> TriggerEdge? {
        guard !isSynthetic else { return nil }
        if hasTriggerFlag {
            // Sticky Keys can keep the flag after the key goes up, so a repeat during a press is checked against the key.
            guard isWaitingForRelease, trustsKeyState else { return .down }
            return isKeyPhysicallyDown() ? .down : .up
        }
        return isKeyPhysicallyDown() ? nil : .up
    }

    // A latched modifier (Sticky Keys) may never report its release, so a key or click with the key up ends the press first.
    public static func releaseMissed(isWaitingForRelease: Bool, trustsKeyState: Bool = true, isKeyPhysicallyDown: () -> Bool) -> Bool {
        isWaitingForRelease && trustsKeyState && !isKeyPhysicallyDown()
    }

    public static let escapeKeyCode: UInt16 = 53

    public static let releaseRecheckDelay: Duration = .milliseconds(100)

    // The key state can be stale (Fn/Globe, remapping tools), so an ignored release gets one more look while a press is in progress.
    public static func shouldRecheckRelease(isSynthetic: Bool, hasTriggerFlag: Bool, isWaitingForRelease: Bool) -> Bool {
        !isSynthetic && !hasTriggerFlag && isWaitingForRelease
    }

    public static func afterRecheck(isKeyPhysicallyDown: Bool) -> TriggerEdge? {
        isKeyPhysicallyDown ? nil : .up
    }

    // Keys and clicks only matter during a press or a recording (a custom shortcut needs just Esc), so idle watches nothing.
    public static func watchesKeys(trigger: TriggerKey, isRecordingActive: Bool, isWaitingForRelease: Bool) -> Bool {
        trigger == .customShortcut ? isRecordingActive : isRecordingActive || isWaitingForRelease
    }
}

// Installs a watch on keys and clicks for the trigger and returns what removes it.
typealias KeyWatchInstaller = @MainActor (TriggerKey, @escaping @MainActor (NSEvent) -> Void) -> @MainActor () -> Void

@MainActor
public final class TriggerMonitor {
    private static let logger = Logger(subsystem: "com.sorla.app", category: "TriggerMonitor")
    private var gesture = PushToTalkGesture()
    private var trigger: TriggerKey
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isCustomShortcutActive = false
    private var isRecordingActive = false
    private var releaseRecheck: Task<Void, Never>?
    private let installKeyWatch: KeyWatchInstaller
    private var removeKeyWatch: (@MainActor () -> Void)?

    public var isSuspended = false {
        didSet {
            guard isSuspended, isSuspended != oldValue else { return }
            releaseRecheck?.cancel()
            if isRecordingActive {
                isRecordingActive = false
                onCancel()
            }
            gesture.reset()
            updateKeyWatch()
        }
    }

    private let onStart: () -> Bool
    private let onFinish: () -> Void
    private let onCancel: () -> Void
    private let onDiscard: () -> Void

    public convenience init(
        trigger: TriggerKey = .default,
        mode: RecordingMode = .pushToTalk,
        onStart: @escaping @MainActor () -> Bool,
        onFinish: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) {
        self.init(
            trigger: trigger,
            mode: mode,
            installKeyWatch: Self.installEventMonitors,
            onStart: onStart,
            onFinish: onFinish,
            onCancel: onCancel,
            onDiscard: onDiscard
        )
    }

    init(
        trigger: TriggerKey,
        mode: RecordingMode,
        installKeyWatch: @escaping KeyWatchInstaller,
        onStart: @escaping @MainActor () -> Bool,
        onFinish: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) {
        self.trigger = trigger
        self.gesture = PushToTalkGesture(mode: mode)
        self.installKeyWatch = installKeyWatch
        self.onStart = onStart
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.onDiscard = onDiscard
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        // Safe: this instance is only ever touched and released from the main actor.
        MainActor.assumeIsolated {
            removeKeyWatch?()
            if isCustomShortcutActive {
                KeyboardShortcuts.removeHandler(for: .sorlaCustomTrigger)
            }
        }
    }

    // A dictation started from the menu is stopped by a clean press and release, not by a ⌘-shortcut's key-down.
    public func recordingDidStartElsewhere() {
        releaseRecheck?.cancel()
        isRecordingActive = true
        gesture.recordingStartedElsewhere()
        updateKeyWatch()
    }

    // A dictation stopped from the menu or at the length limit no longer belongs to the key, so the next press starts a new one.
    public func recordingDidEndElsewhere() {
        releaseRecheck?.cancel()
        isRecordingActive = false
        gesture.reset()
        updateKeyWatch()
    }

    public func configure(trigger: TriggerKey, mode: RecordingMode) {
        if isRecordingActive {
            isRecordingActive = false
            onCancel()
        }

        tearDown()
        self.trigger = trigger
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
        removeKeyWatch?()
        removeKeyWatch = nil
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

    // Only the trigger's own changes are watched all the time; keys and clicks are watched while they matter.
    private func setUpModifierMonitor(for trigger: TriggerKey) {
        guard let keyCode = trigger.keyCode, let deviceMask = trigger.deviceMask else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleFlagsChanged(event, keyCode: keyCode, deviceMask: deviceMask)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleFlagsChanged(event, keyCode: keyCode, deviceMask: deviceMask)
            }
            return event
        }
    }

    private func updateKeyWatch() {
        let isNeeded = !isSuspended && TriggerEdge.watchesKeys(
            trigger: trigger,
            isRecordingActive: isRecordingActive,
            isWaitingForRelease: gesture.isWaitingForRelease
        )
        if isNeeded, removeKeyWatch == nil {
            removeKeyWatch = installKeyWatch(trigger) { [weak self] event in
                self?.handleWatchedEvent(event)
            }
        } else if !isNeeded, let removeKeyWatch {
            removeKeyWatch()
            self.removeKeyWatch = nil
        }
    }

    private static func installEventMonitors(
        for trigger: TriggerKey,
        handler: @escaping @MainActor (NSEvent) -> Void
    ) -> @MainActor () -> Void {
        let mask: NSEvent.EventTypeMask = trigger == .customShortcut
            ? .keyDown
            : [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            MainActor.assumeIsolated { handler(event) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            MainActor.assumeIsolated { handler(event) }
            return event
        }
        return {
            if let global { NSEvent.removeMonitor(global) }
            if let local { NSEvent.removeMonitor(local) }
        }
    }

    private func handleWatchedEvent(_ event: NSEvent) {
        guard !isSuspended, !Self.isSorlaSyntheticEvent(event) else { return }
        guard let keyCode = trigger.keyCode else {
            // The custom shortcut itself comes from KeyboardShortcuts, so only Esc is looked at here.
            if event.keyCode == TriggerEdge.escapeKeyCode, !event.isARepeat { handle(.escape) }
            return
        }
        let isTriggerDown = { CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keyCode)) }
        switch event.type {
        case .keyDown:
            if event.keyCode == TriggerEdge.escapeKeyCode {
                if !event.isARepeat { handle(.escape, isTriggerDown: isTriggerDown) }
            } else {
                handle(.otherKeyDown(at: event.timestamp), isTriggerDown: isTriggerDown)
            }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            handle(.click(at: event.timestamp), isTriggerDown: isTriggerDown)
        default:
            break
        }
    }

    // KeyboardShortcuts only reports down/up of the registered combo, so there's no "other key while held" signal here.
    private func setUpCustomShortcut() {
        isCustomShortcutActive = true

        KeyboardShortcuts.onKeyDown(for: .sorlaCustomTrigger) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isSuspended else { return }
                self.handle(.triggerDown(at: ProcessInfo.processInfo.systemUptime))
            }
        }

        KeyboardShortcuts.onKeyUp(for: .sorlaCustomTrigger) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isSuspended else { return }
                self.handle(.triggerUp(at: ProcessInfo.processInfo.systemUptime))
            }
        }
    }

    private func handleFlagsChanged(_ event: NSEvent, keyCode: UInt16, deviceMask: UInt) {
        guard !isSuspended, event.keyCode == keyCode else { return }
        releaseRecheck?.cancel()
        let isSynthetic = Self.isSorlaSyntheticEvent(event)
        let hasTriggerFlag = event.modifierFlags.rawValue & deviceMask != 0
        let edge = TriggerEdge.forModifierEvent(
            isSynthetic: isSynthetic,
            hasTriggerFlag: hasTriggerFlag,
            isWaitingForRelease: gesture.isWaitingForRelease,
            trustsKeyState: trigger.hasReliableKeyState,
            isKeyPhysicallyDown: { CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keyCode)) }
        )
        switch edge {
        case .down:
            handle(.triggerDown(at: event.timestamp))
        case .up:
            handle(.triggerUp(at: event.timestamp))
        case nil:
            Self.logger.info("trigger flagsChanged ignored: synthetic=\(isSynthetic, privacy: .public) flag=\(hasTriggerFlag, privacy: .public)")
            if TriggerEdge.shouldRecheckRelease(
                isSynthetic: isSynthetic,
                hasTriggerFlag: hasTriggerFlag,
                isWaitingForRelease: gesture.isWaitingForRelease
            ) {
                scheduleReleaseRecheck(keyCode: keyCode)
            }
        }
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

    func handle(_ event: PushToTalkGesture.Event, isTriggerDown: () -> Bool = { true }) {
        switch event {
        case .otherKeyDown(let at), .click(let at):
            deliverMissedRelease(at: at, isTriggerDown: isTriggerDown)
            dispatch(gesture.handle(event))
        case .escape:
            // Esc cancels first, so a lost release can't turn it into a finish.
            dispatch(gesture.handle(event))
            deliverMissedRelease(at: ProcessInfo.processInfo.systemUptime, isTriggerDown: isTriggerDown)
        case .triggerDown, .triggerUp:
            dispatch(gesture.handle(event))
        }
    }

    private func deliverMissedRelease(at time: TimeInterval, isTriggerDown: () -> Bool) {
        guard TriggerEdge.releaseMissed(
            isWaitingForRelease: gesture.isWaitingForRelease,
            trustsKeyState: trigger.hasReliableKeyState,
            isKeyPhysicallyDown: isTriggerDown
        ) else { return }
        Self.logger.info("trigger release missed; delivering it first")
        dispatch(gesture.handle(.triggerUp(at: time)))
    }

    private func dispatch(_ action: PushToTalkGesture.Action?) {
        switch action {
        case .start:
            // Watched before the microphone starts, so the key of a quick ⌘-shortcut isn't missed.
            isRecordingActive = true
            updateKeyWatch()
            if !onStart() {
                isRecordingActive = false
                gesture.reset()
            }
        case .finish:
            isRecordingActive = false
            onFinish()
        case .cancel:
            isRecordingActive = false
            onCancel()
        case .discard:
            isRecordingActive = false
            onDiscard()
        case nil:
            break
        }
        updateKeyWatch()
    }
}
