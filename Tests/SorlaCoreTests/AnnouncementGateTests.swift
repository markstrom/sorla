import XCTest
@testable import SorlaCore

final class AnnouncementGateTests: XCTestCase {
    func testWithTheMicrophoneClosedTheAnnouncementIsMadeAtOnce() {
        var gate = AnnouncementGate()

        XCTAssertEqual(gate.request("Pasting text", isMicrophoneOpen: false), "Pasting text")
        XCTAssertNil(gate.microphoneClosed())
    }

    func testWhileTheMicrophoneIsOpenItWaitsForItToClose() {
        var gate = AnnouncementGate()

        XCTAssertNil(gate.request("Pasting text", isMicrophoneOpen: true))

        XCTAssertEqual(gate.microphoneClosed(), "Pasting text")
        XCTAssertNil(gate.microphoneClosed())
    }

    func testTheNewestWaitingOutcomeIsTheOneSaid() {
        var gate = AnnouncementGate()

        _ = gate.request("Nothing heard", isMicrophoneOpen: true)
        _ = gate.request("Pasting text", isMicrophoneOpen: true)

        XCTAssertEqual(gate.microphoneClosed(), "Pasting text")
    }
}
