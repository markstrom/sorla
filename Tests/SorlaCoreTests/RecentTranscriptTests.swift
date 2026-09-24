import XCTest
@testable import SorlaCore

final class RecentTranscriptTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func testEmptyUntilSomethingIsStored() {
        var recent = RecentTranscript()
        XCTAssertNil(recent.text(at: start))
        XCTAssertNil(recent.expiresAt)
    }

    func testKeepsTheTextForFiveMinutes() {
        var recent = RecentTranscript()
        recent.store("hej", at: start)
        XCTAssertEqual(RecentTranscript.lifetime, 5 * 60)
        XCTAssertEqual(recent.expiresAt, start.addingTimeInterval(5 * 60))
        XCTAssertEqual(recent.text(at: start.addingTimeInterval(5 * 60 - 1)), "hej")
    }

    func testForgetsTheTextOnceExpired() {
        var recent = RecentTranscript()
        recent.store("hej", at: start)
        XCTAssertNil(recent.text(at: start.addingTimeInterval(5 * 60)))
        XCTAssertNil(recent.expiresAt)
        XCTAssertNil(recent.text(at: start), "an expired text stays gone even if the clock goes back")
    }

    func testANewerTranscriptReplacesTheTextAndRestartsTheExpiry() {
        var recent = RecentTranscript()
        recent.store("första", at: start)
        recent.store("andra", at: start.addingTimeInterval(4 * 60))
        XCTAssertEqual(recent.text(at: start.addingTimeInterval(6 * 60)), "andra")
        XCTAssertNil(recent.text(at: start.addingTimeInterval(9 * 60)))
    }

    func testClearForgetsAtOnce() {
        var recent = RecentTranscript()
        recent.store("hej", at: start)
        recent.clear()
        XCTAssertNil(recent.text(at: start))
        XCTAssertNil(recent.expiresAt)
    }

    func testForgetClearsTheTextAndRejectsWorkBegunBefore() {
        var recent = RecentTranscript()
        recent.store("hej", at: start)
        let inFlight = recent.generation
        XCTAssertTrue(recent.accepts(from: inFlight))

        recent.forget()

        XCTAssertNil(recent.text(at: start))
        XCTAssertFalse(recent.accepts(from: inFlight))
        XCTAssertTrue(recent.accepts(from: recent.generation))
    }

    // Expiry only ends the text's lifetime; a dictation still being transcribed is kept.
    func testExpiryAndClearDoNotRejectWorkInFlight() {
        var recent = RecentTranscript()
        let inFlight = recent.generation
        recent.store("hej", at: start)
        _ = recent.text(at: start.addingTimeInterval(RecentTranscript.lifetime))
        recent.clear()
        XCTAssertTrue(recent.accepts(from: inFlight))
    }
}
