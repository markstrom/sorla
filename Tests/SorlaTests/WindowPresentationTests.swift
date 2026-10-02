import XCTest
@testable import Sorla

final class WindowPresentationTests: XCTestCase {
    // #86: started inside the status menu's tracking, activation is undone when the menu gives the focus back.
    @MainActor
    func testAWindowWaitsUntilTheMenuHasStoppedTracking() {
        var ran = false
        SorlaWindow.afterMenuTracking { ran = true }

        _ = RunLoop.main.run(mode: .eventTracking, before: Date().addingTimeInterval(0.01))
        XCTAssertFalse(ran, "nothing may come forward inside the menu's tracking loop")
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        XCTAssertTrue(ran)
    }

    func testAWindowShownWhileSorlaIsActiveShowsAtOnce() {
        var presentation = WindowPresentation()
        let request = presentation.request()

        XCTAssertEqual(presentation.bringForward(request, isAppActive: true), .show)
        XCTAssertFalse(presentation.appDidBecomeActive(request))
    }

    func testAWindowWaitingForActivationIsShownOnceSorlaIsActive() {
        var presentation = WindowPresentation()
        let request = presentation.request()

        XCTAssertEqual(presentation.bringForward(request, isAppActive: false), .waitForActivation)
        XCTAssertTrue(presentation.appDidBecomeActive(request))
        XCTAssertFalse(presentation.appDidBecomeActive(request))
    }

    // The bug: About closed while its activation was declined came back when Settings later activated Sorla.
    func testAWindowClosedWhileWaitingIsNotBroughtBackByALaterActivation() {
        var presentation = WindowPresentation()
        let request = presentation.request()
        _ = presentation.bringForward(request, isAppActive: false)

        presentation.end(request)

        XCTAssertFalse(presentation.appDidBecomeActive(request))
        XCTAssertEqual(presentation.retry(request, isAppActive: true, hasSwitchedApp: false), .none)
    }

    func testAWindowClosedBeforeItsTurnIsNotShown() {
        var presentation = WindowPresentation()
        let request = presentation.request()

        presentation.end(request)

        XCTAssertEqual(presentation.bringForward(request, isAppActive: false), .none)
        XCTAssertFalse(presentation.appDidBecomeActive(request))
    }

    func testOpeningAgainAfterClosingShowsIt() {
        var presentation = WindowPresentation()
        let closed = presentation.request()
        presentation.end(closed)

        let reopened = presentation.request()

        XCTAssertFalse(presentation.isCurrent(closed), "a callback queued for the closed request does nothing")
        XCTAssertEqual(presentation.bringForward(closed, isAppActive: true), .none)
        XCTAssertEqual(presentation.bringForward(reopened, isAppActive: true), .show)
    }

    // #86: About asked for, then Settings before Sorla became active; only Settings may take the focus.
    func testOnlyTheNewestRequestMayRaiseAWindow() {
        var presentation = WindowPresentation()
        let about = presentation.request()
        _ = presentation.bringForward(about, isAppActive: false)

        let settings = presentation.request()

        XCTAssertFalse(presentation.isCurrent(about))
        XCTAssertTrue(presentation.isCurrent(settings))
        XCTAssertEqual(presentation.bringForward(about, isAppActive: false), .none)
        // An old callback's cleanup must not end the newer request.
        presentation.end(about)
        XCTAssertTrue(presentation.isCurrent(settings))
        XCTAssertEqual(presentation.bringForward(settings, isAppActive: false), .waitForActivation)
        XCTAssertFalse(presentation.appDidBecomeActive(about))
        XCTAssertTrue(presentation.appDidBecomeActive(settings))
    }

    // #86: an activation that never comes ends the request, so a later one for something else raises nothing.
    func testADeclinedActivationIsRetriedAFewTimesThenGivenUp() {
        var presentation = WindowPresentation()
        let request = presentation.request()
        _ = presentation.bringForward(request, isAppActive: false)

        for _ in 0..<WindowPresentation.maximumRetries {
            XCTAssertEqual(presentation.retry(request, isAppActive: false, hasSwitchedApp: false), .waitForActivation)
        }
        XCTAssertEqual(presentation.retry(request, isAppActive: false, hasSwitchedApp: false), .none)
        XCTAssertFalse(presentation.isCurrent(request))
        XCTAssertFalse(presentation.appDidBecomeActive(request))
    }

    func testAnActivationSeenWithoutItsNotificationFinishesTheRequest() {
        var presentation = WindowPresentation()
        let request = presentation.request()
        _ = presentation.bringForward(request, isAppActive: false)

        XCTAssertEqual(presentation.retry(request, isAppActive: true, hasSwitchedApp: false), .show)
        XCTAssertFalse(presentation.isWaitingForActivation)
        XCTAssertFalse(presentation.appDidBecomeActive(request), "the notification arriving afterwards doesn't finish it twice")
    }

    // #86: the user moved on, so the window doesn't take the focus from the app they went to.
    func testSwitchingToAnotherAppGivesUpEvenIfSorlaBecameActive() {
        var presentation = WindowPresentation()
        let request = presentation.request()
        _ = presentation.bringForward(request, isAppActive: false)

        XCTAssertEqual(presentation.retry(request, isAppActive: true, hasSwitchedApp: true), .none)
        XCTAssertFalse(presentation.isCurrent(request))
        XCTAssertFalse(presentation.appDidBecomeActive(request))
    }

    func testANewRequestGetsRetriesOfItsOwn() {
        var presentation = WindowPresentation()
        let first = presentation.request()
        _ = presentation.bringForward(first, isAppActive: false)
        for _ in 0...WindowPresentation.maximumRetries {
            _ = presentation.retry(first, isAppActive: false, hasSwitchedApp: false)
        }

        let second = presentation.request()
        _ = presentation.bringForward(second, isAppActive: false)

        XCTAssertEqual(presentation.retry(second, isAppActive: false, hasSwitchedApp: false), .waitForActivation)
    }
}
