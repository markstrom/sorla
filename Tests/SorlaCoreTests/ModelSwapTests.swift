import XCTest
@testable import SorlaCore

final class ModelSwapTests: XCTestCase {
    private var modelsDirectory: URL!
    private var swap: ModelSwap!
    private var staged: URL!

    override func setUpWithError() throws {
        modelsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("sorla-swap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        swap = ModelSwap(modelsDirectory: modelsDirectory)
        staged = modelsDirectory.appendingPathComponent(".staging/pianissimo-sv-1.1.0/model")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: modelsDirectory)
    }

    func testPaths() {
        XCTAssertEqual(swap.installed.lastPathComponent, "pianissimo-sv-coreml")
        XCTAssertEqual(swap.previous.lastPathComponent, "pianissimo-sv-coreml.old")
        XCTAssertEqual(swap.failed.lastPathComponent, "pianissimo-sv-coreml.failed")
        XCTAssertEqual(swap.trash.lastPathComponent, "pianissimo-sv-coreml.trash")
        XCTAssertEqual(swap.installed.deletingLastPathComponent().path, modelsDirectory.path)
    }

    func testSuccessfulSwapLeavesOnlyTheNewModel() throws {
        try makeModel(at: swap.installed, marker: "old")
        try makeModel(at: staged, marker: "new")

        try swap.install(staged)
        XCTAssertEqual(marker(at: swap.previous), "old")
        try swap.commit()

        XCTAssertEqual(marker(at: swap.installed), "new")
        XCTAssertFalse(exists(swap.previous))
        XCTAssertFalse(exists(staged))
    }

    func testFirstInstallNeedsNoPreviousModel() throws {
        try makeModel(at: staged, marker: "new")

        try swap.install(staged)
        try swap.commit()

        XCTAssertEqual(marker(at: swap.installed), "new")
        XCTAssertFalse(exists(swap.previous))
    }

    func testFailedSwapKeepsTheOldModel() throws {
        try makeModel(at: swap.installed, marker: "old")

        XCTAssertThrowsError(try swap.install(staged)) { error in
            XCTAssertEqual(error as? ModelInstallError, .installFailed)
        }

        XCTAssertEqual(marker(at: swap.installed), "old")
        XCTAssertFalse(exists(swap.previous))
    }

    func testALeftoverPreviousModelIsRestoredBeforeTheSwapAndKeptAsTheFallback() throws {
        try makeModel(at: swap.previous, marker: "good")
        try makeModel(at: swap.installed, marker: "unconfirmed")
        try makeModel(at: staged, marker: "new")

        XCTAssertTrue(try swap.install(staged))

        XCTAssertEqual(marker(at: swap.installed), "new")
        XCTAssertEqual(marker(at: swap.previous), "good")
        XCTAssertFalse(exists(swap.failed))
    }

    func testInstallAfterARollbackThatLeftOnlyThePreviousModelKeepsIt() throws {
        try makeModel(at: swap.previous, marker: "good")
        try makeModel(at: swap.failed, marker: "new, partly deleted")
        try makeModel(at: staged, marker: "new")

        XCTAssertTrue(try swap.install(staged))

        XCTAssertEqual(marker(at: swap.installed), "new")
        XCTAssertEqual(marker(at: swap.previous), "good")
        XCTAssertFalse(exists(swap.failed))
        try swap.rollback()
        XCTAssertEqual(marker(at: swap.installed), "good")
    }

    func testInstallReportsWhetherItReplacedAModel() throws {
        try makeModel(at: staged, marker: "first")
        XCTAssertFalse(try swap.install(staged))

        try makeModel(at: staged, marker: "second")
        XCTAssertTrue(try swap.install(staged))
    }

    func testCommitRemovesThePreviousModelAndAnyTrash() throws {
        try makeModel(at: swap.installed, marker: "new")
        try makeModel(at: swap.previous, marker: "old")
        try makeModel(at: swap.trash, marker: "leftover")

        try swap.commit()

        XCTAssertEqual(marker(at: swap.installed), "new")
        XCTAssertFalse(exists(swap.previous))
        XCTAssertFalse(exists(swap.trash))
    }

    func testRollbackRestoresTheOldModel() throws {
        try makeModel(at: swap.installed, marker: "old")
        try makeModel(at: staged, marker: "new")
        try swap.install(staged)

        try swap.rollback()

        XCTAssertEqual(marker(at: swap.installed), "old")
        XCTAssertFalse(exists(swap.previous))
    }

    func testRollbackOfAFirstInstallRemovesTheNewModel() throws {
        try makeModel(at: staged, marker: "new")
        try swap.install(staged)

        try swap.rollback()

        XCTAssertFalse(exists(swap.installed))
    }

    func testRecoveryRestoresAModelLeftHalfwayThroughASwap() throws {
        try makeModel(at: swap.previous, marker: "old")

        try swap.recoverInterruptedSwap()

        XCTAssertEqual(marker(at: swap.installed), "old")
        XCTAssertFalse(exists(swap.previous))
    }

    func testRecoveryNeverKeepsAnUnconfirmedModelOverThePreviousOne() throws {
        try makeModel(at: swap.previous, marker: "old")
        try makeModel(at: swap.installed, marker: "new, never loaded")
        try Data(#"{"models":[{"id":"pianissimo-sv","version":"1.1.0"}]}"#.utf8).write(to: swap.installed.appendingPathComponent("manifest.json"))

        XCTAssertEqual(try swap.recoverInterruptedSwap(), "1.1.0")

        XCTAssertEqual(marker(at: swap.installed), "old")
        XCTAssertFalse(exists(swap.previous))
        XCTAssertFalse(exists(swap.failed))
    }

    private enum Slot: CaseIterable { case installed, previous, failed, trash }

    private func url(_ slot: Slot) -> URL {
        switch slot {
        case .installed: return swap.installed
        case .previous: return swap.previous
        case .failed: return swap.failed
        case .trash: return swap.trash
        }
    }

    // Each on-disk state a crash can leave behind; "good" is the model that must survive.
    func testTheGoodModelSurvivesAnInterruptionAtEveryStep() throws {
        let states: [(step: String, slots: [Slot: String])] = [
            ("install, before the first rename", [.installed: "good"]),
            ("install, after moving the installed model aside", [.previous: "good"]),
            ("install, after moving the new model in (also while it loads)", [.installed: "new", .previous: "good"]),
            ("install, with a stale failed copy left over", [.installed: "new", .previous: "good", .failed: "stale, partly deleted"]),
            ("commit, while deleting a stale trash copy", [.installed: "new", .previous: "good", .trash: "stale, partly deleted"]),
            ("commit, after renaming previous to trash", [.installed: "good", .trash: "old"]),
            ("commit, partway through deleting the trash", [.installed: "good", .trash: "old, partly deleted"]),
            ("rollback, after moving the new model aside", [.failed: "new", .previous: "good"]),
            ("rollback, after restoring the previous model", [.installed: "good", .failed: "new"]),
            ("rollback, partway through deleting the failed model", [.installed: "good", .failed: "new, partly deleted"]),
            ("recovery, partway through deleting trash before rolling back", [.installed: "new", .previous: "good", .trash: "partly deleted"]),
            ("recovery, while deleting a leftover failed copy", [.installed: "good", .failed: "partly deleted"]),
        ]
        for (step, slots) in states {
            try? FileManager.default.removeItem(at: modelsDirectory)
            for (slot, marker) in slots {
                try makeModel(at: url(slot), marker: marker)
            }

            for attempt in 1...2 {
                try swap.recoverInterruptedSwap()

                XCTAssertEqual(marker(at: swap.installed), "good", "\(step), recovery \(attempt)")
                for slot in Slot.allCases where slot != .installed {
                    XCTAssertFalse(exists(url(slot)), "\(step): \(slot) left behind")
                }
            }
        }
    }

    func testRecoveryLeavesANormalInstallAlone() throws {
        try makeModel(at: swap.installed, marker: "current")

        try swap.recoverInterruptedSwap()

        XCTAssertEqual(marker(at: swap.installed), "current")
    }

    func testRollbackMovesTheNewModelAsideBeforeRestoringTheOldOne() throws {
        try makeModel(at: swap.installed, marker: "old")
        try makeModel(at: staged, marker: "new")
        try swap.install(staged)
        try makeModel(at: swap.failed, marker: "leftover")

        try swap.rollback()

        XCTAssertEqual(marker(at: swap.installed), "old")
        XCTAssertFalse(exists(swap.previous))
        XCTAssertFalse(exists(swap.failed))
    }

    func testRecoveryAfterARollbackCutShortBeforeTheOldModelWasBack() throws {
        try makeModel(at: swap.failed, marker: "new, partly deleted")
        try makeModel(at: swap.previous, marker: "old")

        try swap.recoverInterruptedSwap()

        XCTAssertEqual(marker(at: swap.installed), "old")
        XCTAssertFalse(exists(swap.previous))
        XCTAssertFalse(exists(swap.failed))
    }

    func testRecoveryPrefersTheOldModelWheneverAFailedOneExists() throws {
        try makeModel(at: swap.installed, marker: "new")
        try makeModel(at: swap.failed, marker: "new, partly deleted")
        try makeModel(at: swap.previous, marker: "old")

        try swap.recoverInterruptedSwap()

        XCTAssertEqual(marker(at: swap.installed), "old")
        XCTAssertFalse(exists(swap.previous))
        XCTAssertFalse(exists(swap.failed))
    }

    func testRecoveryAfterARollbackCutShortDuringCleanupKeepsTheRestoredModel() throws {
        try makeModel(at: swap.installed, marker: "old")
        try makeModel(at: swap.failed, marker: "new, partly deleted")

        try swap.recoverInterruptedSwap()

        XCTAssertEqual(marker(at: swap.installed), "old")
        XCTAssertFalse(exists(swap.failed))
    }

    private func makeModel(at url: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: url.appendingPathComponent("marker"))
    }

    private func marker(at url: URL) -> String? {
        (try? Data(contentsOf: url.appendingPathComponent("marker"))).map { String(decoding: $0, as: UTF8.self) }
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
