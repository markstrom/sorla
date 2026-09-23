import XCTest
@testable import PrataCore

final class MenuStatusRowTests: XCTestCase {
    private func row(
        microphoneDenied: Bool = false,
        accessibilityMissing: Bool = false,
        model: ModelStatus = .installed(version: "1.0.0"),
        modelLoadFailed: Bool = false
    ) -> MenuStatusRow? {
        MenuStatusRow.current(
            microphoneDenied: microphoneDenied,
            accessibilityMissing: accessibilityMissing,
            model: model,
            modelLoadFailed: modelLoadFailed
        )
    }

    func testNothingToShowHidesTheRow() {
        XCTAssertNil(row())
        XCTAssertNil(row(model: .upToDate(version: "1.0.0")))
        XCTAssertNil(row(model: .checking))
        XCTAssertNil(row(model: .checkFailed(.network)))
    }

    func testMicrophoneComesFirst() {
        let row = row(microphoneDenied: true, accessibilityMissing: true, model: .failed(.network, isUpdate: false), modelLoadFailed: true)

        XCTAssertEqual(row, MenuStatusRow(title: "Microphone access needed", action: .openMicrophoneSettings))
    }

    func testAccessibilityComesBeforeTheModel() {
        let row = row(accessibilityMissing: true, model: .downloading(version: "1.0.0", fraction: 0.5, isUpdate: false))

        XCTAssertEqual(row, MenuStatusRow(title: "Accessibility access needed to paste", action: .openAccessibilitySettings))
    }

    func testDownloadProgressComesBeforeFailures() {
        XCTAssertEqual(
            row(model: .downloading(version: "1.0.0", fraction: 0.34, isUpdate: false), modelLoadFailed: true),
            MenuStatusRow(title: "Downloading Swedish model… 34%", action: .openSettings)
        )
        XCTAssertEqual(
            row(model: .preparing(version: "1.0.0", isUpdate: false)),
            MenuStatusRow(title: "Preparing Swedish model…", action: .openSettings)
        )
        XCTAssertEqual(
            row(model: .waitingToInstall(version: "1.1.0")),
            MenuStatusRow(title: "Preparing Swedish model…", action: .openSettings)
        )
    }

    func testFailedDownloadOffersARetry() {
        XCTAssertEqual(
            row(model: .failed(.network, isUpdate: false)),
            MenuStatusRow(title: "Swedish model download failed — Try Again", action: .downloadModel)
        )
        XCTAssertEqual(
            row(model: .failed(.selfTestFailed, isUpdate: true)),
            MenuStatusRow(title: "Model update failed — Try Again", action: .downloadModel)
        )
    }

    func testMissingModelOffersADownload() {
        XCTAssertEqual(
            row(model: .notInstalled),
            MenuStatusRow(title: "Swedish model not installed — Download", action: .downloadModel)
        )
    }

    func testLoadFailureOpensSettings() {
        XCTAssertEqual(
            row(modelLoadFailed: true),
            MenuStatusRow(title: "Swedish model couldn't be loaded", action: .openSettings)
        )
    }

    func testFailuresComeBeforeAnAvailableUpdate() {
        XCTAssertEqual(row(model: .updateAvailable(version: "1.1.0"), modelLoadFailed: true)?.action, .openSettings)
    }

    func testAvailableUpdateComesLast() {
        XCTAssertEqual(
            row(model: .updateAvailable(version: "1.1.0")),
            MenuStatusRow(title: "Model update available (1.1.0)", action: .downloadModel)
        )
    }
}
