import XCTest
@testable import Sorla

final class ModelLoadingStatusTests: XCTestCase {
    func testLoadingShowsTheHourglassRegardlessOfRecordingState() {
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .loading, isRecording: false).symbolName,
            "hourglass"
        )
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .loading, isRecording: true).symbolName,
            "hourglass"
        )
    }

    // The bug this fixes: a failed load must not leave the hourglass showing forever.
    func testFailedEndsTheLoadingStateAndShowsTheIdleMicIcon() {
        let icon = ModelLoadingStatus.menuBarIcon(for: .failed, isRecording: false)
        XCTAssertEqual(icon.symbolName, "mic")
        XCTAssertNotEqual(icon.symbolName, "hourglass")
    }

    func testFailedWhileRecordingStillShowsTheRecordingIcon() {
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .failed, isRecording: true).symbolName,
            "mic.fill"
        )
    }

    func testReadyShowsTheIdleMicIcon() {
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .ready, isRecording: false).symbolName,
            "mic"
        )
    }

    func testReadyWhileRecordingShowsTheRecordingIcon() {
        XCTAssertEqual(
            ModelLoadingStatus.menuBarIcon(for: .ready, isRecording: true).symbolName,
            "mic.fill"
        )
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
