import XCTest
@testable import Sorla

final class WindowPresentationTests: XCTestCase {
    func testAWindowShownWhileSorlaIsActiveShowsAtOnce() {
        var presentation = WindowPresentation()
        presentation.request()

        XCTAssertEqual(presentation.bringForward(isAppActive: true), .show)
        XCTAssertFalse(presentation.appDidBecomeActive())
    }

    func testAWindowWaitingForActivationIsShownOnceSorlaIsActive() {
        var presentation = WindowPresentation()
        presentation.request()

        XCTAssertEqual(presentation.bringForward(isAppActive: false), .waitForActivation)
        XCTAssertTrue(presentation.appDidBecomeActive())
        XCTAssertFalse(presentation.appDidBecomeActive())
    }

    // The bug: About closed while its activation was declined came back when Settings later activated Sorla.
    func testAWindowClosedWhileWaitingIsNotBroughtBackByALaterActivation() {
        var presentation = WindowPresentation()
        presentation.request()
        _ = presentation.bringForward(isAppActive: false)

        presentation.close()

        XCTAssertFalse(presentation.appDidBecomeActive())
    }

    func testAWindowClosedBeforeItsTurnIsNotShown() {
        var presentation = WindowPresentation()
        presentation.request()

        presentation.close()

        XCTAssertEqual(presentation.bringForward(isAppActive: false), .none)
        XCTAssertFalse(presentation.appDidBecomeActive())
    }

    func testOpeningAgainAfterClosingShowsIt() {
        var presentation = WindowPresentation()
        presentation.request()
        presentation.close()

        presentation.request()

        XCTAssertEqual(presentation.bringForward(isAppActive: true), .show)
    }
}
