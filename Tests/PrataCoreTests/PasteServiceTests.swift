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

    func testWriteToPasteboardReturnsChangeCountAfterWrite() {
        let changeCount = PasteService.writeToPasteboard("text", pasteboard: pasteboard)

        XCTAssertEqual(changeCount, pasteboard.changeCount)
    }

    func testSnapshotRestoreRoundTripPreservesItemsTypesAndOrder() {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let stringItem = NSPasteboardItem()
        stringItem.setString("hello clipboard", forType: .string)
        let pngItem = NSPasteboardItem()
        pngItem.setData(pngData, forType: .png)
        pasteboard.clearContents()
        pasteboard.writeObjects([stringItem, pngItem])

        let snapshot = PasteService.snapshot(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("overwritten", forType: .string)

        PasteService.restore(snapshot, to: pasteboard)

        let items = pasteboard.pasteboardItems ?? []
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].string(forType: .string), "hello clipboard")
        XCTAssertEqual(items[1].data(forType: .png), pngData)
    }

    func testSnapshotRestoreRoundTripEmptyPasteboardStaysEmpty() {
        pasteboard.clearContents()
        let snapshot = PasteService.snapshot(of: pasteboard)

        pasteboard.setString("something", forType: .string)
        PasteService.restore(snapshot, to: pasteboard)

        XCTAssertEqual(pasteboard.pasteboardItems?.count ?? 0, 0)
    }

    func testShouldRestoreClipboardWhenKeepSettingOffReturnsFalse() {
        XCTAssertFalse(PasteService.shouldRestoreClipboard(
            keepSetting: false, pasteDelivered: true, changeCountAfterWrite: 1, currentChangeCount: 1
        ))
    }

    func testShouldRestoreClipboardWhenPasteNotDeliveredReturnsFalse() {
        XCTAssertFalse(PasteService.shouldRestoreClipboard(
            keepSetting: true, pasteDelivered: false, changeCountAfterWrite: 1, currentChangeCount: 1
        ))
    }

    func testShouldRestoreClipboardWhenChangeCountChangedReturnsFalse() {
        XCTAssertFalse(PasteService.shouldRestoreClipboard(
            keepSetting: true, pasteDelivered: true, changeCountAfterWrite: 1, currentChangeCount: 2
        ))
    }

    func testShouldRestoreClipboardWhenAllConditionsMetReturnsTrue() {
        XCTAssertTrue(PasteService.shouldRestoreClipboard(
            keepSetting: true, pasteDelivered: true, changeCountAfterWrite: 3, currentChangeCount: 3
        ))
    }

    func testIsSyntheticMarkerMatchesOwnMarker() {
        XCTAssertTrue(PasteService.isSyntheticMarker(PasteService.syntheticEventMarker))
    }

    func testIsSyntheticMarkerRejectsOtherValues() {
        XCTAssertFalse(PasteService.isSyntheticMarker(0))
        XCTAssertFalse(PasteService.isSyntheticMarker(PasteService.syntheticEventMarker + 1))
    }

    func testShouldAutoPasteWhenFrontmostAppUnchangedReturnsTrue() {
        XCTAssertTrue(PasteService.shouldAutoPaste(frontmostPIDAtRelease: 100, frontmostPIDAtDelivery: 100))
    }

    func testShouldAutoPasteWhenFrontmostAppChangedReturnsFalse() {
        XCTAssertFalse(PasteService.shouldAutoPaste(frontmostPIDAtRelease: 100, frontmostPIDAtDelivery: 200))
    }

    func testShouldAutoPasteWhenEitherPIDUnknownReturnsTrue() {
        XCTAssertTrue(PasteService.shouldAutoPaste(frontmostPIDAtRelease: nil, frontmostPIDAtDelivery: 200))
        XCTAssertTrue(PasteService.shouldAutoPaste(frontmostPIDAtRelease: 100, frontmostPIDAtDelivery: nil))
    }
}
