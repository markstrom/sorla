import XCTest
import AppKit
@testable import PrataCore

final class PasteServiceTests: XCTestCase {
    private var savedClipboard: String?

    override func setUp() {
        savedClipboard = NSPasteboard.general.string(forType: .string)
    }

    override func tearDown() {
        NSPasteboard.general.clearContents()
        if let savedClipboard {
            NSPasteboard.general.setString(savedClipboard, forType: .string)
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
