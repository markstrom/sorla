import XCTest
@testable import SorlaCore

final class ModelManifestTests: XCTestCase {
    func testDecodesThePublishedManifest() throws {
        let manifest = try ModelManifest.decode(Data(ManifestFixtures.published.utf8))

        XCTAssertEqual(manifest.schema, 1)
        let release = try XCTUnwrap(manifest.release(id: ModelManifest.pianissimoID))
        XCTAssertEqual(release.id, "pianissimo-sv")
        XCTAssertEqual(release.name, "Pianissimo (Swedish)")
        XCTAssertEqual(release.version, "1.0.0")
        XCTAssertEqual(release.totalSize, 688_257_471)
        XCTAssertEqual(release.loader, ModelLoader(library: "FluidAudio", version: "v3"))
        XCTAssertEqual(release.files.count, 15)
        let encoderWeights = try XCTUnwrap(release.files.first { $0.path == "Encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin" })
        XCTAssertEqual(encoderWeights.size, 649_181_632)
        XCTAssertEqual(encoderWeights.sha256, "e9623b969e8f31ba12bfbec7cdcdacb3bfb74e5a3a9bd3a812e4a942c1b1b9ed")
    }

    func testThePublishedReleaseIsValid() throws {
        let manifest = try ModelManifest.decode(Data(ManifestFixtures.published.utf8))
        let release = try XCTUnwrap(manifest.release(id: ModelManifest.pianissimoID))

        XCTAssertNoThrow(try release.validate())
        XCTAssertTrue(release.isCompatible)
        XCTAssertEqual(release.packageNames, ["Decoder", "Encoder", "JointDecisionv3", "Preprocessor"])
    }

    func testUnknownModelIDIsNotFound() throws {
        let manifest = try ModelManifest.decode(Data(ManifestFixtures.published.utf8))

        XCTAssertNil(manifest.release(id: "something-else"))
    }

    func testGarbageIsRejected() {
        XCTAssertThrowsError(try ModelManifest.decode(Data("<html>".utf8)))
    }

    func testPathsThatEscapeTheStagingDirectoryAreRejected() {
        for path in ["../evil", "Encoder.mlpackage/../../evil", "/etc/passwd", "", "a//b"] {
            let release = Self.release(files: [ModelFile(path: path, size: 1, sha256: String(repeating: "a", count: 64))])
            XCTAssertThrowsError(try release.validate(), "accepted \(path)")
        }
    }

    func testMalformedHashesAreRejected() {
        for hash in ["abc", String(repeating: "g", count: 64), String(repeating: "A", count: 63)] {
            let release = Self.release(files: [ModelFile(path: "parakeet_vocab.json", size: 1, sha256: hash)])
            XCTAssertThrowsError(try release.validate(), "accepted \(hash)")
        }
    }

    func testAReleaseWithoutTheVocabularyIsRejected() {
        let release = Self.release(files: [ModelFile(path: "Encoder.mlpackage/Manifest.json", size: 1, sha256: String(repeating: "a", count: 64))])

        XCTAssertThrowsError(try release.validate())
    }

    func testAnUnparsableVersionIsRejected() {
        let release = Self.release(version: "latest")

        XCTAssertThrowsError(try release.validate())
    }

    func testOtherLoadersAreIncompatible() {
        XCTAssertFalse(Self.release(loader: ModelLoader(library: "FluidAudio", version: "v4")).isCompatible)
        XCTAssertFalse(Self.release(loader: ModelLoader(library: "WhisperKit", version: "v3")).isCompatible)
        XCTAssertFalse(Self.release(loader: nil).isCompatible)
    }

    static func release(
        version: String = "1.0.0",
        loader: ModelLoader? = ModelLoader(library: "FluidAudio", version: "v3"),
        files: [ModelFile] = [ModelFile(path: "parakeet_vocab.json", size: 1, sha256: String(repeating: "a", count: 64))]
    ) -> ModelRelease {
        ModelRelease(id: "pianissimo-sv", name: "Pianissimo (Swedish)", version: version, loader: loader, totalSize: files.reduce(0) { $0 + $1.size }, files: files)
    }
}
