import AppKit
import KeyboardShortcuts

public extension KeyboardShortcuts.Name {
    static let prataCustomTrigger = Self("prataCustomTrigger")
}

@MainActor
public final class TriggerMonitor {
    private var gesture = PushToTalkGesture()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isCustomShortcutActive = false
    private var isRecordingActive = false

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
        // KeyboardShortcuts.removeHandler(for:) is MainActor-isolated; deinit itself isn't, but this
        // instance is only ever touched and released from the main actor, so the assumption holds.
        if isCustomShortcutActive {
            MainActor.assumeIsolated {
                KeyboardShortcuts.removeHandler(for: .prataCustomTrigger)
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
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if isCustomShortcutActive {
            KeyboardShortcuts.removeHandler(for: .prataCustomTrigger)
            isCustomShortcutActive = false
        }
    }

    private func setUpModifierMonitor(for trigger: TriggerKey) {
        guard let keyCode = trigger.keyCode, let deviceMask = trigger.deviceMask else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]

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

        KeyboardShortcuts.onKeyDown(for: .prataCustomTrigger) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.dispatch(self.gesture.handle(.triggerDown(at: ProcessInfo.processInfo.systemUptime)))
            }
        }

        KeyboardShortcuts.onKeyUp(for: .prataCustomTrigger) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.dispatch(self.gesture.handle(.triggerUp(at: ProcessInfo.processInfo.systemUptime)))
            }
        }
    }

    private func handleModifierEvent(_ event: NSEvent, keyCode: UInt16, deviceMask: UInt) {
        let action: PushToTalkGesture.Action?

        switch event.type {
        case .flagsChanged:
            guard event.keyCode == keyCode else { return }
            let isDown = event.modifierFlags.rawValue & deviceMask != 0
            action = gesture.handle(isDown ? .triggerDown(at: event.timestamp) : .triggerUp(at: event.timestamp))
        case .keyDown:
            action = gesture.handle(.otherKeyDown)
        default:
            return
        }

        dispatch(action)
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
