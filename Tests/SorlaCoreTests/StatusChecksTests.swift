import XCTest
@testable import SorlaCore

// #76: the icon and the menu row don't repeat the permission and model file checks on every download progress tick.
final class StatusChecksTests: XCTestCase {
    private let allowed = StatusChecks(isMicrophoneAccessDenied: false, isAccessibilityTrusted: true, isModelInstalled: false)
    private let missing = StatusChecks(isMicrophoneAccessDenied: false, isAccessibilityTrusted: false, isModelInstalled: false)

    private func downloading(_ fraction: Double, version: String = "2", isUpdate: Bool = false) -> ModelStatus {
        .downloading(version: version, fraction: fraction, isUpdate: isUpdate)
    }

    func testOnlyTheSameDownloadMovingOnIsAProgressTick() {
        XCTAssertTrue(downloading(0.2).isProgressTick(after: downloading(0.1)))
        XCTAssertFalse(downloading(0.1).isProgressTick(after: .checking), "the download starting")
        XCTAssertFalse(ModelStatus.preparing(version: "2", isUpdate: false).isProgressTick(after: downloading(1)), "done downloading")
        XCTAssertFalse(downloading(0.2, version: "3").isProgressTick(after: downloading(0.1)), "another version")
        XCTAssertFalse(downloading(0.2, isUpdate: true).isProgressTick(after: downloading(0.1)), "another kind of download")
        XCTAssertFalse(ModelStatus.notInstalled.isProgressTick(after: .notInstalled))
    }

    func testProgressTicksReuseTheLastReading() {
        var cache = StatusCheckCache()
        var reads = 0
        var current = allowed
        let read = { () -> StatusChecks in reads += 1; return current }

        XCTAssertEqual(cache.checks(model: downloading(0.1), read: read), allowed)
        current = missing
        XCTAssertEqual(cache.checks(model: downloading(0.2), read: read), allowed)
        XCTAssertEqual(cache.checks(model: downloading(0.3), read: read), allowed)
        XCTAssertEqual(reads, 1)
    }

    // App activation, the menu opening and phase changes always read again, and so does a tick after them.
    func testEveryOtherRefreshReadsAgain() {
        var cache = StatusCheckCache()
        var reads = 0
        var current = allowed
        let read = { () -> StatusChecks in reads += 1; return current }

        _ = cache.checks(model: downloading(0.1), read: read)
        current = missing
        XCTAssertEqual(cache.checks(model: nil, read: read), missing, "the user came back from System Settings")
        XCTAssertEqual(cache.checks(model: downloading(0.2), read: read), missing, "the tick uses the new reading")
        XCTAssertEqual(reads, 2)

        current = allowed
        XCTAssertEqual(cache.checks(model: .preparing(version: "2", isUpdate: false), read: read), allowed)
        XCTAssertEqual(reads, 3)
    }

    func testTheFirstRefreshReadsEvenForATick() {
        var cache = StatusCheckCache()
        var reads = 0
        _ = cache.checks(model: downloading(0.5)) { reads += 1; return allowed }
        XCTAssertEqual(reads, 1)
    }
}
