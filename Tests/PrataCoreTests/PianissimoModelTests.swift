import XCTest

@testable import PrataCore

final class SpeechModelTests: XCTestCase {
    func testRawValuesAreStableForPersistence() {
        XCTAssertEqual(SpeechModel.parakeet.rawValue, "parakeet")
        XCTAssertEqual(SpeechModel.pianissimo.rawValue, "pianissimo")
    }

    func testParakeetIsAlwaysInstalled() {
        XCTAssertTrue(SpeechModel.parakeet.isInstalled)
    }

    func testPianissimoIsNotInstalledWhenDirectoryIsEmpty() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertFalse(SpeechModel.hasRequiredFiles(at: directory))
    }

    func testPianissimoIsNotInstalledWhenSomeFilesAreMissing() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        for name in ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc"] {
            FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: nil)
        }

        XCTAssertFalse(SpeechModel.hasRequiredFiles(at: directory))
    }

    func testPianissimoIsInstalledWhenAllRequiredFilesArePresent() throws {
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

        XCTAssertTrue(SpeechModel.hasRequiredFiles(at: directory))
    }

    func testDisplayNames() {
        XCTAssertEqual(SpeechModel.parakeet.displayName, "Parakeet v3 (multilingual)")
        XCTAssertEqual(SpeechModel.pianissimo.displayName, "Pianissimo (Swedish)")
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("prata-speech-model-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
