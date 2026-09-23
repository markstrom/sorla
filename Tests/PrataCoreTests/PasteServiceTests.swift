import XCTest
import AppKit
@testable import PrataCore

final class PasteServiceTests: XCTestCase {
    private var savedPasteboardItems: [[NSPasteboard.PasteboardType: Data]]?

    override func setUp() {
        let items = NSPasteboard.general.pasteboardItems ?? []
        savedPasteboardItems = items.map { item in
            var itemData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData[type] = data
                }
            }
            return itemData
        }
    }

    override func tearDown() {
        NSPasteboard.general.clearContents()
        if let savedPasteboardItems, !savedPasteboardItems.isEmpty {
            let items = savedPasteboardItems.map { itemData -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in itemData {
                    item.setData(data, forType: type)
                }
                return item
            }
            NSPasteboard.general.writeObjects(items)
        }
    }

    func testWriteToPasteboardPutsTextOnGeneralPasteboard() {
        let expected = "Prata testtranskript \(UUID().uuidString)"

        PasteService.writeToPasteboard(expected)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), expected)
    }

    func testWriteToPasteboardReplacesPreviousContent() {
        PasteService.writeToPasteboard("första")
        PasteService.writeToPasteboard("andra")

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "andra")
    }
}
