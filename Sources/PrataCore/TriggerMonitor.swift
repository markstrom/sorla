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

    private let onStart: () -> Void
    private let onFinish: () -> Void
    private let onCancel: () -> Void

    public init(
        onStart: @escaping @MainActor () -> Void,
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

    // The KeyboardShortcuts library only reports down/up of the registered combo itself, so
    // there is no "other key while held" signal available for a custom shortcut the way there
    // is for a bare modifier trigger observed via NSEvent monitors.
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
            isRecordingActive = true
            onStart()
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
