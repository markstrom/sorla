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

    func testKeepsLegacyFoldersThatStillHaveOtherContent() throws {
        try makeModel(at: legacyModel, marker: "legacy")
        try fileManager.createDirectory(at: legacyApp.appendingPathComponent("Models/other"), withIntermediateDirectories: true)

        XCTAssertTrue(try LegacyModelMigration.migrate(applicationSupport: base))

        XCTAssertEqual(marker(at: model), "legacy")
        XCTAssertTrue(fileManager.fileExists(atPath: legacyApp.appendingPathComponent("Models/other").path))
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
