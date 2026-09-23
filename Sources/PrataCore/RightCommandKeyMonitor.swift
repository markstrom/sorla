import AppKit

@MainActor
public final class RightCommandKeyMonitor {
    private static let rightCommandKeyCode: UInt16 = 0x36
    private static let rightCommandDeviceMask: UInt = 0x10

    private var gesture = PushToTalkGesture()
    private var globalMonitor: Any?
    private var localMonitor: Any?
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

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return event
        }
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private func handle(_ event: NSEvent) {
        let action: PushToTalkGesture.Action?

        switch event.type {
        case .flagsChanged:
            guard event.keyCode == Self.rightCommandKeyCode else { return }
            let isDown = event.modifierFlags.rawValue & Self.rightCommandDeviceMask != 0
            action = gesture.handle(isDown ? .triggerDown(at: event.timestamp) : .triggerUp(at: event.timestamp))
        case .keyDown:
            action = gesture.handle(.otherKeyDown)
        default:
            return
        }

        switch action {
        case .start:
            onStart()
        case .finish:
            onFinish()
        case .cancel:
            onCancel()
        case nil:
            break
        }
    }
}
