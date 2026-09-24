import XCTest
@testable import SorlaCore

@MainActor
final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "sorla-app-settings-tests-\(UUID().uuidString)"
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

    func testUpdateTogglesDefaultToOff() {
        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.autoCheckUpdates)
        XCTAssertFalse(settings.autoInstallUpdates)
    }

    func testUpdateTogglesPersistImmediatelyAndRoundTrip() {
        let settings = AppSettings(defaults: defaults)

        settings.autoCheckUpdates = true
        settings.autoInstallUpdates = true

        XCTAssertEqual(defaults.object(forKey: "autoCheckUpdates") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "autoInstallUpdates") as? Bool, true)
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.autoCheckUpdates)
        XCTAssertTrue(reloaded.autoInstallUpdates)
    }

    func testTheOldModelTogglesBecomeTheUpdateToggles() {
        defaults.set(true, forKey: "autoCheckModelUpdates")
        defaults.set(true, forKey: "autoDownloadModelUpdates")

        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.autoCheckUpdates)
        XCTAssertTrue(settings.autoInstallUpdates)
        XCTAssertEqual(defaults.object(forKey: "autoCheckUpdates") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "autoInstallUpdates") as? Bool, true)
        XCTAssertNil(defaults.object(forKey: "autoCheckModelUpdates"))
        XCTAssertNil(defaults.object(forKey: "autoDownloadModelUpdates"))
    }

    func testAnOldToggleThatWasOffStaysOff() {
        defaults.set(true, forKey: "autoCheckModelUpdates")
        defaults.set(false, forKey: "autoDownloadModelUpdates")

        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.autoCheckUpdates)
        XCTAssertFalse(settings.autoInstallUpdates)
    }

    func testANewToggleValueWinsOverALeftoverOldOne() {
        defaults.set(false, forKey: "autoCheckUpdates")
        defaults.set(true, forKey: "autoCheckModelUpdates")

        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.autoCheckUpdates)
        XCTAssertNil(defaults.object(forKey: "autoCheckModelUpdates"))
    }

    func testOnboardingIsNotCompletedByDefault() {
        XCTAssertFalse(AppSettings(defaults: defaults).hasCompletedOnboarding)
    }

    func testOnboardingCompletionPersistsImmediatelyAndRoundTrips() {
        let settings = AppSettings(defaults: defaults)

        settings.hasCompletedOnboarding = true

        XCTAssertEqual(defaults.object(forKey: "hasCompletedOnboarding") as? Bool, true)
        XCTAssertTrue(AppSettings(defaults: defaults).hasCompletedOnboarding)
    }
}
