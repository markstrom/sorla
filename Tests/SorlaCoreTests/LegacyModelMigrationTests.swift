import XCTest

@testable import SorlaCore

final class LegacyModelMigrationTests: XCTestCase {
    private var base: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        base = fileManager.temporaryDirectory.appendingPathComponent("sorla-migration-tests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: base)
    }

    private var legacyApp: URL { base.appendingPathComponent(LegacyModelMigration.legacyAppFolderName) }
    private var legacyModel: URL { legacyApp.appendingPathComponent("Models/pianissimo-sv-coreml") }
    private var model: URL { base.appendingPathComponent("Sorla/Models/pianissimo-sv-coreml") }

    private func makeModel(at directory: URL, marker: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try marker.write(to: directory.appendingPathComponent("marker"), atomically: true, encoding: .utf8)
    }

    private func marker(at directory: URL) -> String? {
        try? String(contentsOf: directory.appendingPathComponent("marker"), encoding: .utf8)
    }

    func testLegacyFolderNameIsTheFormerAppName() {
        XCTAssertEqual(LegacyModelMigration.legacyAppFolderName, "Prata")
    }

    func testMovesLegacyModelAndRemovesEmptyLegacyFolders() throws {
        try makeModel(at: legacyModel, marker: "legacy")

        XCTAssertTrue(try LegacyModelMigration.migrate(applicationSupport: base))

        XCTAssertEqual(marker(at: model), "legacy")
        XCTAssertFalse(fileManager.fileExists(atPath: legacyApp.path))
    }

    func testKeepsTheLegacyAppFolderWhenItHasOtherContent() throws {
        try makeModel(at: legacyModel, marker: "legacy")
        try fileManager.createDirectory(at: legacyApp.appendingPathComponent("other"), withIntermediateDirectories: true)

        XCTAssertTrue(try LegacyModelMigration.migrate(applicationSupport: base))

        XCTAssertEqual(marker(at: model), "legacy")
        XCTAssertTrue(fileManager.fileExists(atPath: legacyApp.appendingPathComponent("other").path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacyApp.appendingPathComponent("Models").path))
    }

    func testMovesSwapLeftoversAndStagingSoRecoveryCanFinishThem() throws {
        let legacyModels = legacyApp.appendingPathComponent("Models")
        try makeModel(at: legacyModels.appendingPathComponent("pianissimo-sv-coreml.old"), marker: "good")
        try makeModel(at: legacyModels.appendingPathComponent("pianissimo-sv-coreml.failed"), marker: "bad, partly deleted")
        try makeModel(at: legacyModels.appendingPathComponent(".staging/pianissimo-sv-1.1.0/download"), marker: "partial")

        XCTAssertTrue(try LegacyModelMigration.migrate(applicationSupport: base))

        let models = model.deletingLastPathComponent()
        XCTAssertTrue(fileManager.fileExists(atPath: models.appendingPathComponent(".staging/pianissimo-sv-1.1.0/download").path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacyApp.path))
        try ModelSwap(modelsDirectory: models).recoverInterruptedSwap()
        XCTAssertEqual(marker(at: model), "good")
        XCTAssertFalse(fileManager.fileExists(atPath: models.appendingPathComponent("pianissimo-sv-coreml.failed").path))
    }

    func testDoesNothingWhenTheNewModelsFolderExistsEvenWithoutAModel() throws {
        try makeModel(at: legacyModel, marker: "legacy")
        try fileManager.createDirectory(at: model.deletingLastPathComponent(), withIntermediateDirectories: true)

        XCTAssertFalse(try LegacyModelMigration.migrate(applicationSupport: base))

        XCTAssertEqual(marker(at: legacyModel), "legacy")
    }

    func testDoesNothingWhenTheNewModelAlreadyExists() throws {
        try makeModel(at: legacyModel, marker: "legacy")
        try makeModel(at: model, marker: "current")

        XCTAssertFalse(try LegacyModelMigration.migrate(applicationSupport: base))

        XCTAssertEqual(marker(at: model), "current")
        XCTAssertEqual(marker(at: legacyModel), "legacy")
    }

    func testDoesNothingWithoutALegacyModel() throws {
        XCTAssertFalse(try LegacyModelMigration.migrate(applicationSupport: base))
        XCTAssertFalse(fileManager.fileExists(atPath: model.path))
    }
}
