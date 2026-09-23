import AppKit

public struct PasteboardSnapshot {
    public struct Item {
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

public enum PasteService {
    @discardableResult
    public static func writeToPasteboard(_ text: String, pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.clearContents()
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

    // Without Accessibility permission the OS drops these events; the text stays on the pasteboard.
    public static func paste() {
        let virtualKeyV: CGKeyCode = 0x09
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
