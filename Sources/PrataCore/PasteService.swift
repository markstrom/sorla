import AppKit

public struct PasteboardSnapshot: Equatable {
    public struct Item: Equatable {
        public var data: [NSPasteboard.PasteboardType: Data]

        public init(data: [NSPasteboard.PasteboardType: Data]) {
            self.data = data
        }
    }

    public var items: [Item]

    public init(items: [Item]) {
        self.items = items
    }
}

public struct ClipboardOwnershipTracker {
    public struct Begin: Equatable {
        public let original: PasteboardSnapshot
        public let generation: Int
    }

    public enum FinishAction: Equatable {
        case skip
        case evaluate(original: PasteboardSnapshot)
    }

    public private(set) var pendingOriginal: PasteboardSnapshot?
    public private(set) var generation = 0

    public init() {}

    public mutating func begin(capture: () -> PasteboardSnapshot) -> Begin {
        let original = pendingOriginal ?? capture()
        pendingOriginal = original
        generation += 1
        return Begin(original: original, generation: generation)
    }

    public mutating func cancel() {
        pendingOriginal = nil
    }

    public mutating func finish(generation: Int) -> FinishAction {
        guard generation == self.generation, let original = pendingOriginal else {
            return .skip
        }
        pendingOriginal = nil
        return .evaluate(original: original)
    }
}

public enum PasteService {
    // Tags CGEvents Prata posts so TriggerMonitor can tell its own synthetic ⌘V apart from a real key.
    public static let syntheticEventMarker: Int64 = 0x50726174

    public static func isSyntheticMarker(_ value: Int64) -> Bool {
        value == syntheticEventMarker
    }

    private static let transientPasteboardType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    @discardableResult
    public static func writeToPasteboard(_ text: String, pasteboard: NSPasteboard = .general, transient: Bool = false) -> Int {
        pasteboard.clearContents()
        if transient {
            pasteboard.setData(Data(), forType: transientPasteboardType)
        }
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    public static func snapshot(of pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item -> PasteboardSnapshot.Item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let value = item.data(forType: type) {
                    data[type] = value
                }
            }
            return PasteboardSnapshot.Item(data: data)
        }
        return PasteboardSnapshot(items: items)
    }

    public static func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let items = snapshot.items.map { snapshotItem -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in snapshotItem.data {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    public static func shouldRestoreClipboard(
        keepSetting: Bool,
        pasteDelivered: Bool,
        changeCountAfterWrite: Int,
        currentChangeCount: Int
    ) -> Bool {
        keepSetting && pasteDelivered && changeCountAfterWrite == currentChangeCount
    }

    // Frontmost app may have changed between key release and transcript delivery; paste would land in the wrong place.
    public static func shouldAutoPaste(frontmostPIDAtRelease: pid_t?, frontmostPIDAtDelivery: pid_t?) -> Bool {
        guard let frontmostPIDAtRelease, let frontmostPIDAtDelivery else { return true }
        return frontmostPIDAtRelease == frontmostPIDAtDelivery
    }

    // Without Accessibility permission the OS drops these events; the text stays on the pasteboard.
    public static func paste() {
        let virtualKeyV: CGKeyCode = 0x09
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
