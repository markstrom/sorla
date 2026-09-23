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
        XCTAssertEqual(swap.installed.deletingLastPathComponent().path, modelsDirectory.path)
    }

    func testSuccessfulSwapLeavesOnlyTheNewModel() throws {
        try makeModel(at: swap.installed, marker: "old")
        try makeModel(at: staged, marker: "new")

        try swap.install(staged)
        XCTAssertEqual(marker(at: swap.previous), "old")
        swap.commit()

        XCTAssertEqual(marker(at: swap.installed), "new")
        XCTAssertFalse(exists(swap.previous))
        XCTAssertFalse(exists(staged))
    }

    func testFirstInstallNeedsNoPreviousModel() throws {
        try makeModel(at: staged, marker: "new")

        try swap.install(staged)
        swap.commit()

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

    func testALeftoverPreviousDirectoryDoesNotBlockTheSwap() throws {
        try makeModel(at: swap.previous, marker: "ancient")
        try makeModel(at: swap.installed, marker: "old")
        try makeModel(at: staged, marker: "new")

        try swap.install(staged)

        XCTAssertEqual(marker(at: swap.installed), "new")
        XCTAssertEqual(marker(at: swap.previous), "old")
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

        swap.recoverInterruptedSwap()

        XCTAssertEqual(marker(at: swap.installed), "old")
        XCTAssertFalse(exists(swap.previous))
    }

    func testRecoveryFinishesACompletedSwap() throws {
        try makeModel(at: swap.previous, marker: "old")
        try makeModel(at: swap.installed, marker: "new")

        swap.recoverInterruptedSwap()

        XCTAssertEqual(marker(at: swap.installed), "new")
        XCTAssertFalse(exists(swap.previous))
    }

    func testRecoveryLeavesANormalInstallAlone() throws {
        try makeModel(at: swap.installed, marker: "current")

        swap.recoverInterruptedSwap()

        XCTAssertEqual(marker(at: swap.installed), "current")
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
