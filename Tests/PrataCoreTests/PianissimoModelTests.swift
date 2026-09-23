import XCTest

@testable import PrataCore

final class PianissimoModelTests: XCTestCase {
    func testDisplayName() {
        XCTAssertEqual(PianissimoModel.displayName, "Pianissimo (Swedish)")
    }

    func testIsNotInstalledWhenDirectoryIsEmpty() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertFalse(PianissimoModel.hasRequiredFiles(at: directory))
    }

    func testIsNotInstalledWhenSomeFilesAreMissing() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        for name in ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc"] {
            FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: nil)
        }

        XCTAssertFalse(PianissimoModel.hasRequiredFiles(at: directory))
    }

    func testIsInstalledWhenAllRequiredFilesArePresent() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let requiredNames = [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecisionv3.mlmodelc",
            "parakeet_vocab.json",
        ]
        for name in requiredNames {
            FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: nil)
        }

        XCTAssertTrue(PianissimoModel.hasRequiredFiles(at: directory))
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("prata-pianissimo-model-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testInstalledVersionIsReadFromTheManifest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = #"{"schema":1,"models":[{"id":"pianissimo-sv","version":"1.2.3"}]}"#
        try manifest.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        XCTAssertEqual(PianissimoModel.installedVersion(at: directory), "1.2.3")
    }

    func testInstalledVersionIsNilWithoutAManifest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNil(PianissimoModel.installedVersion(at: directory))
    }

    func testThePublishedManifestInstalledOnDiskIsUpToDate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(ManifestFixtures.published.utf8).write(to: directory.appendingPathComponent("manifest.json"))
        let latest = try XCTUnwrap(ModelManifest.decode(Data(ManifestFixtures.published.utf8)).release(id: ModelManifest.pianissimoID))

        let installed = PianissimoModel.installedVersion(at: directory)

        XCTAssertEqual(installed, "1.0.0")
        XCTAssertEqual(ModelUpdatePolicy.decide(installedVersion: installed, isInstalled: true, latest: latest, autoDownload: true), .none)
    }

    func testInstalledVersionPrefersThePianissimoEntry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = #"{"schema":1,"models":[{"id":"other","version":"9.9.9"},{"id":"pianissimo-sv","version":"1.2.3"}]}"#
        try manifest.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        XCTAssertEqual(PianissimoModel.installedVersion(at: directory), "1.2.3")
    }
}
