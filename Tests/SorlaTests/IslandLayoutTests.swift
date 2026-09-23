import XCTest
@testable import Sorla

final class IslandLayoutTests: XCTestCase {
    // 5 bars of 3pt with 3pt gaps (27pt) plus 10pt padding on each edge.
    func testNotchSideWidthFitsTheWaveformPlusPadding() {
        let layout = IslandLayout.notchLayout(notchWidth: 200, notchHeight: 32)
        XCTAssertEqual(layout.sideWidth, 47)
    }

    func testNotchLayoutIsExactlyAsTallAsTheNotch() {
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
        XCTAssertEqual(layout.maxBarHeight, 32 - 12)
    }

    func testNotchMaxBarHeightNeverDropsBelowMinBarHeight() {
        let layout = IslandLayout.notchLayout(notchWidth: 200, notchHeight: 4)
        XCTAssertEqual(layout.maxBarHeight, 3)
    }

    func testCompactLayoutHangsSlightlyBelowTheMenuBar() {
        let layout = IslandLayout.compactLayout(menuBarHeight: 24)
        XCTAssertEqual(layout.notchWidth, 0)
        XCTAssertEqual(layout.sideWidth, 0)
        XCTAssertEqual(layout.height, 24 + IslandLayout.depthBelowMenuBar)
        XCTAssertEqual(layout.size, NSSize(width: IslandLayout.compactWidth, height: 24 + IslandLayout.depthBelowMenuBar))
    }

    func testCompactLayoutFallsBackToThirtyWhenMenuBarHeightIsZero() {
        let layout = IslandLayout.compactLayout(menuBarHeight: 0)
        XCTAssertEqual(layout.height, 30 + IslandLayout.depthBelowMenuBar)
    }

    func testNotchCollapsedWidthIsExactlyTheNotchSoItHidesBlackOnBlack() {
        let layout = IslandLayout.notchLayout(notchWidth: 200, notchHeight: 32)
        XCTAssertEqual(layout.collapsedSize, NSSize(width: 200, height: 32))
    }

    func testCompactCollapsedSizeIsASmallPillAtFullHeight() {
        let layout = IslandLayout.compactLayout(menuBarHeight: 24)
        XCTAssertEqual(layout.collapsedSize, NSSize(width: 36, height: 24 + IslandLayout.depthBelowMenuBar))
    }

    func testPanelLeavesRoomOnBothSidesForTheSpringOvershoot() {
        let layout = IslandLayout.notchLayout(notchWidth: 200, notchHeight: 32)
        XCTAssertEqual(layout.panelSize.width, layout.size.width + 2 * IslandLayout.overshootMargin)
        XCTAssertEqual(layout.panelSize.height, layout.size.height)
        XCTAssertGreaterThan(IslandLayout.overshootMargin, 0)
    }
}
