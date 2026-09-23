import XCTest
@testable import PrataCore

@MainActor
final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "prata-app-settings-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testDefaultsWhenNothingPersisted() {
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.triggerKey, .rightCommand)
        XCTAssertEqual(settings.recordingMode, .pushToTalk)
        XCTAssertTrue(settings.keepClipboardContent)
        XCTAssertTrue(settings.playSounds)
    }

    func testPlaySoundsPersistsImmediatelyAndRoundTrips() {
        let settings = AppSettings(defaults: defaults)

        settings.playSounds = false

        XCTAssertEqual(defaults.object(forKey: "playSounds") as? Bool, false)
        XCTAssertFalse(AppSettings(defaults: defaults).playSounds)
    }

    func testTriggerKeyPersistsImmediatelyAndRoundTrips() {
        let settings = AppSettings(defaults: defaults)

        settings.triggerKey = .fn

        XCTAssertEqual(defaults.string(forKey: "triggerKey"), "fn")
        XCTAssertEqual(AppSettings(defaults: defaults).triggerKey, .fn)
    }

    func testRecordingModePersistsImmediatelyAndRoundTrips() {
        let settings = AppSettings(defaults: defaults)

        settings.recordingMode = .toggle

        XCTAssertEqual(defaults.string(forKey: "recordingMode"), "toggle")
        XCTAssertEqual(AppSettings(defaults: defaults).recordingMode, .toggle)
    }

    func testKeepClipboardContentPersistsImmediatelyAndRoundTrips() {
        let settings = AppSettings(defaults: defaults)

        settings.keepClipboardContent = false

        XCTAssertEqual(defaults.object(forKey: "keepClipboardContent") as? Bool, false)
        XCTAssertFalse(AppSettings(defaults: defaults).keepClipboardContent)
    }

    func testInvalidPersistedTriggerKeyFallsBackToDefault() {
        defaults.set("not-a-real-trigger", forKey: "triggerKey")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.triggerKey, .rightCommand)
    }

    func testInvalidPersistedRecordingModeFallsBackToDefault() {
        defaults.set("not-a-real-mode", forKey: "recordingMode")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.recordingMode, .pushToTalk)
    }
}
