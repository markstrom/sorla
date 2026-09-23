import XCTest
@testable import Prata

final class IslandLayoutTests: XCTestCase {
    // Side content is 5 bars (3pt wide, 3pt spacing) = 27pt, wider than the 16pt dot/spinner,
    // so each side is 27 + 10pt (notch-side padding) + 10pt (outer-edge padding) = 47pt.
    func testNotchSideWidthFitsTheWaveformPlusPadding() {
        let layout = IslandLayout.notchLayout(notchWidth: 200, notchHeight: 32)
        XCTAssertEqual(layout.sideWidth, 47)
    }

    func testNotchHeightIsExactlyTheNotchHeightWithNoExtraDepth() {
        let layout = IslandLayout.notchLayout(notchWidth: 200, notchHeight: 32)
        XCTAssertEqual(layout.height, 32)
    }

    func testNotchTotalSizeIsNotchWidthPlusBothSides() {
        let layout = IslandLayout.notchLayout(notchWidth: 200, notchHeight: 32)
        XCTAssertEqual(layout.size.width, 200 + 2 * 47)
        XCTAssertEqual(layout.size.height, 32)
    }

    func testNotchSideWidthIsIndependentOfNotchWidth() {
        let narrow = IslandLayout.notchLayout(notchWidth: 120, notchHeight: 37)
        let wide = IslandLayout.notchLayout(notchWidth: 260, notchHeight: 37)
        XCTAssertEqual(narrow.sideWidth, wide.sideWidth)
    }

    func testNotchMaxBarHeightIsScaledToNotchHeight() {
        let layout = IslandLayout.notchLayout(notchWidth: 200, notchHeight: 32)
        XCTAssertEqual(layout.notchMaxBarHeight, 20)
    }

    func testNotchMaxBarHeightNeverDropsBelowMinBarHeight() {
        let layout = IslandLayout.notchLayout(notchWidth: 200, notchHeight: 10)
        XCTAssertEqual(layout.notchMaxBarHeight, 3)
    }

    func testCompactLayoutIsUnchangedForScreensWithoutANotch() {
        let layout = IslandLayout.compactLayout(menuBarHeight: 24)
        XCTAssertEqual(layout.notchWidth, 0)
        XCTAssertEqual(layout.sideWidth, 0)
        XCTAssertEqual(layout.height, 24 + IslandLayout.extraDepth)
        XCTAssertEqual(layout.size, NSSize(width: IslandLayout.compactWidth, height: 24 + IslandLayout.extraDepth))
    }

    func testCompactLayoutFallsBackToThirtyWhenMenuBarHeightIsZero() {
        let layout = IslandLayout.compactLayout(menuBarHeight: 0)
        XCTAssertEqual(layout.height, 30 + IslandLayout.extraDepth)
    }
}
