import XCTest
import AppKit
@testable import PrataCore

final class PasteServiceTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        pasteboard = NSPasteboard.withUniqueName()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
    }

    func testWriteToPasteboardPutsTextOnPasteboard() {
        let expected = "Prata testtranskript \(UUID().uuidString)"

        PasteService.writeToPasteboard(expected, pasteboard: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), expected)
    }

    func testWriteToPasteboardReplacesPreviousContent() {
        PasteService.writeToPasteboard("första", pasteboard: pasteboard)
        PasteService.writeToPasteboard("andra", pasteboard: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "andra")
    }
}
