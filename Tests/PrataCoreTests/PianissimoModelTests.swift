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
}
