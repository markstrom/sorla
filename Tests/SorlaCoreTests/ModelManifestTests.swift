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

    func testDecodesThePublishedCompiledManifest() throws {
        let release = try XCTUnwrap(ModelManifest.decode(Data(ManifestFixtures.compiled.utf8)).release(id: ModelManifest.pianissimoID))

        XCTAssertEqual(release.version, "1.1.0")
        XCTAssertEqual(release.format, "mlmodelc")
        XCTAssertEqual(release.modelFormat, .compiled)
        XCTAssertEqual(release.minimumOS, ModelMinimumOS(macOS: "26.0"))
        XCTAssertEqual(release.totalSize, 688_595_324)
        XCTAssertEqual(release.files.count, 22)
        XCTAssertEqual(release.compiledModelNames, ["Decoder", "Encoder", "JointDecisionv3", "Preprocessor"])
        XCTAssertEqual(release.packageNames, [])
        XCTAssertTrue(release.isCompatible)
        let encoderWeights = try XCTUnwrap(release.files.first { $0.path == "Encoder.mlmodelc/weights/weight.bin" })
        XCTAssertEqual(encoderWeights.size, 649_181_632)
        XCTAssertEqual(encoderWeights.sha256, "e9623b969e8f31ba12bfbec7cdcdacb3bfb74e5a3a9bd3a812e4a942c1b1b9ed")
    }

    func testAPackageReleaseWithoutAFormatIsPackages() throws {
        let release = try XCTUnwrap(ModelManifest.decode(Data(ManifestFixtures.published.utf8)).release(id: ModelManifest.pianissimoID))

        XCTAssertNil(release.format)
        XCTAssertNil(release.minimumOS)
        XCTAssertEqual(release.modelFormat, .packages)
        XCTAssertNoThrow(try release.validate(runningOn: .sonoma))
    }

    func testAnUnknownFormatIsRejected() {
        let release = Self.release(format: "onnx")

        XCTAssertNil(release.modelFormat)
        XCTAssertThrowsError(try release.validate(runningOn: .tahoe))
    }

    func testAnUnmetMinimumMacOSIsRejected() {
        let release = Self.compiledRelease()

        XCTAssertNoThrow(try release.validate(runningOn: .tahoe))
        XCTAssertNoThrow(try release.validate(runningOn: SemanticVersion(major: 27, minor: 0, patch: 0)))
        XCTAssertThrowsError(try release.validate(runningOn: .sequoia))
        XCTAssertThrowsError(try release.validate(runningOn: SemanticVersion(major: 25, minor: 9, patch: 9)))
    }

    func testAMinimumMacOSAlsoAppliesToPackages() {
        let release = Self.release(minimumOS: ModelMinimumOS(macOS: "15.0"))

        XCTAssertNoThrow(try release.validate(runningOn: .sequoia))
        XCTAssertThrowsError(try release.validate(runningOn: .sonoma))
    }

    func testAnUnreadableMinimumMacOSIsRejected() {
        XCTAssertThrowsError(try Self.compiledRelease(minimumOS: ModelMinimumOS(macOS: "twenty-six")).validate(runningOn: .tahoe))
    }

    func testACompiledReleaseMustStateItsMinimumMacOS() {
        XCTAssertThrowsError(try Self.compiledRelease(minimumOS: nil).validate(runningOn: .tahoe))
        XCTAssertThrowsError(try Self.compiledRelease(minimumOS: ModelMinimumOS(macOS: nil)).validate(runningOn: .tahoe))
    }

    func testACompiledReleaseMustContainAllFourModels() {
        for missing in ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"] {
            let release = Self.compiledRelease(models: ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"].filter { $0 != missing })
            XCTAssertThrowsError(try release.validate(runningOn: .tahoe), "accepted a release without \(missing)")
        }
    }

    func testACompiledReleaseMayNotContainPackages() {
        let package = ModelFile(path: "Encoder.mlpackage/Manifest.json", size: 1, sha256: String(repeating: "a", count: 64))

        XCTAssertThrowsError(try Self.compiledRelease(extraFiles: [package]).validate(runningOn: .tahoe))
    }

    func testCompiledPathsThatEscapeTheManifestFolderAreRejected() {
        for path in ["../Encoder.mlmodelc/model.mil", "Encoder.mlmodelc/../../evil", "/Encoder.mlmodelc/model.mil", "./Encoder.mlmodelc/model.mil"] {
            let escape = ModelFile(path: path, size: 1, sha256: String(repeating: "a", count: 64))
            XCTAssertThrowsError(try Self.compiledRelease(extraFiles: [escape]).validate(runningOn: .tahoe), "accepted \(path)")
        }
    }

    func testAPathListedTwiceIsRejected() {
        let files = [Self.vocabulary(size: 1), Self.vocabulary(size: 1)]

        XCTAssertThrowsError(try Self.release(files: files).validate())
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

    func testATotalSizeThatDoesNotMatchTheFilesIsRejected() {
        XCTAssertThrowsError(try Self.release(totalSize: 2).validate())
        XCTAssertThrowsError(try Self.release(totalSize: 0).validate())
    }

    func testANegativeOrHugeTotalSizeIsRejected() {
        XCTAssertThrowsError(try Self.release(totalSize: -1).validate())
        let huge = ModelRelease.maximumTotalSize + 1
        XCTAssertThrowsError(try Self.release(totalSize: huge, files: [Self.vocabulary(size: huge)]).validate())
    }

    func testFileSizesThatOverflowWhenAddedAreRejected() {
        let files = [Self.vocabulary(size: .max), ModelFile(path: "README.md", size: .max, sha256: String(repeating: "a", count: 64))]

        XCTAssertThrowsError(try Self.release(totalSize: 1, files: files).validate())
        XCTAssertNil(ModelRelease.checkedSum([.max, 1]))
        XCTAssertEqual(ModelRelease.checkedSum([1, 2, 3]), 6)
    }

    static func vocabulary(size: Int64) -> ModelFile {
        ModelFile(path: "parakeet_vocab.json", size: size, sha256: String(repeating: "a", count: 64))
    }

    static func release(
        version: String = "1.0.0",
        loader: ModelLoader? = ModelLoader(library: "FluidAudio", version: "v3"),
        totalSize: Int64? = nil,
        files: [ModelFile] = [vocabulary(size: 1)],
        format: String? = nil,
        minimumOS: ModelMinimumOS? = nil
    ) -> ModelRelease {
        ModelRelease(
            id: "pianissimo-sv", name: "Pianissimo (Swedish)", version: version, loader: loader,
            totalSize: totalSize ?? ModelRelease.checkedSum(files.map(\.size)) ?? 0, files: files,
            format: format, minimumOS: minimumOS
        )
    }

    static func compiledRelease(
        models: [String] = ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"],
        extraFiles: [ModelFile] = [],
        minimumOS: ModelMinimumOS? = ModelMinimumOS(macOS: "26.0")
    ) -> ModelRelease {
        let modelFiles = models.map { ModelFile(path: "\($0).mlmodelc/coremldata.bin", size: 1, sha256: String(repeating: "a", count: 64)) }
        return release(version: "1.1.0", files: modelFiles + [vocabulary(size: 1)] + extraFiles, format: "mlmodelc", minimumOS: minimumOS)
    }
}
