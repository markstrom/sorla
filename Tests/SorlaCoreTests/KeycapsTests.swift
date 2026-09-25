import XCTest
@testable import SorlaCore

// #75: the key names the window sets apart as keycaps.
final class KeycapsTests: XCTestCase {
    private func found(_ keys: [String], in text: String) -> [String] {
        Keycaps.ranges(of: keys, in: text).map { String(text[$0]) }
    }

    func testFindsEachKeyInTheSentence() {
        XCTAssertEqual(found(["Right ⌘"], in: "Sorla is ready. Hold Right ⌘ to dictate."), ["Right ⌘"])
        XCTAssertEqual(found(["Fn"], in: "Sorla är redo. Håll Fn för att diktera."), ["Fn"])
        XCTAssertEqual(found(["⌘V"], in: "Close this window and press ⌘V where you were typing."), ["⌘V"])
    }

    func testTheLongerShortcutWinsAndNothingOverlaps() {
        XCTAssertEqual(found(["V", "⌃⌥V"], in: "Paste Last (⌃⌥V) or V"), ["⌃⌥V", "V"])
    }

    func testNoKeyNoRange() {
        XCTAssertEqual(found([], in: "Fix the items above to try dictation."), [])
        XCTAssertEqual(found([""], in: "Anything"), [])
        XCTAssertEqual(found(["Right ⌘"], in: "Fix the items above to try dictation."), [])
    }
}
