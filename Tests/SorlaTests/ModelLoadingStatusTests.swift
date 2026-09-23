import XCTest
@testable import Sorla

final class ModelLoadingStatusTests: XCTestCase {
    func testLoadingShowsTheLoadingGlyphRegardlessOfRecordingState() {
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .loading, isRecording: false).glyph,
            .loading
        )
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .loading, isRecording: true).glyph,
            .loading
        )
    }

    // The bug this fixes: a failed load must not leave the loading glyph showing forever.
    func testFailedEndsTheLoadingStateAndShowsTheMark() {
        let icon = ModelLoadingStatus.menuBarIcon(for: .failed, isRecording: false)
        XCTAssertEqual(icon.glyph, .ready)
        XCTAssertNotEqual(icon.glyph, .loading)
    }

    func testFailedWhileRecordingShowsTheMark() {
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .failed, isRecording: true).glyph,
            .ready
        )
    }

    func testReadyShowsTheMark() {
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .ready, isRecording: false).glyph,
            .ready
        )
    }

    func testReadyWhileRecordingShowsTheMark() {
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .ready, isRecording: true).glyph,
            .ready
        )
    }

    func testTheGlyphIsATemplateImageSoItFollowsTheMenuBarAppearance() {
        for glyph in [MenuBarGlyph.ready, .loading] {
            let image = glyph.image(accessibilityDescription: "Sorla")
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size.height, 18)
        }
    }

    func testAccessibilityDescriptionsAreDistinctPerState() {
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .loading, isRecording: false).accessibilityDescription,
            "Sorla (loading model)"
        )
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .ready, isRecording: false).accessibilityDescription,
            "Sorla"
        )
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .ready, isRecording: true).accessibilityDescription,
            "Sorla (recording)"
        )
    }
}
