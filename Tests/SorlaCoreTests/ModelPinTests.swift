import XCTest
@testable import SorlaCore

final class ModelPinTests: XCTestCase {
    func testMacOS14To25KeepsThePackageRelease() {
        for system in [SemanticVersion.sonoma, .sequoia, SemanticVersion(major: 25, minor: 9, patch: 9)] {
            XCTAssertEqual(ModelPins.forSystem(system), ModelPins(preferred: .packages), "\(system)")
        }
    }

    func testMacOS26AndLaterUseTheCompiledRelease() {
        for system in [SemanticVersion.tahoe, SemanticVersion(major: 26, minor: 1, patch: 0), SemanticVersion(major: 27, minor: 0, patch: 0)] {
            XCTAssertEqual(ModelPins.forSystem(system), ModelPins(preferred: .compiled, fallback: .packages), "\(system)")
        }
    }

    func testThePackagePinIsTheUnchanged100Release() {
        XCTAssertEqual(ModelPin.packages.version, "1.0.0")
        XCTAssertEqual(
            ModelPin.packages.manifestURL.absoluteString,
            "https://huggingface.co/markstrom/pianissimo-sv-coreml/resolve/106fa163a138a0db6737e0c50494269e07f508d0/manifest.json"
        )
        XCTAssertEqual(
            ModelPin.packages.fileURL(for: "Encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin").absoluteString,
            "https://huggingface.co/markstrom/pianissimo-sv-coreml/resolve/106fa163a138a0db6737e0c50494269e07f508d0/Encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin"
        )
        XCTAssertTrue(ModelPin.packages.matches(Data(ManifestFixtures.published.utf8)))
    }

    func testTheCompiledPinFetchesFilesRelativeToItsManifestFolder() {
        XCTAssertEqual(ModelPin.compiled.version, "1.1.0")
        XCTAssertEqual(
            ModelPin.compiled.manifestURL.absoluteString,
            "https://huggingface.co/markstrom/pianissimo-sv-coreml/resolve/dd578628d1ae6577b4672221b99fff59112ff5b4/compiled/1.1.0/manifest.json"
        )
        XCTAssertEqual(
            ModelPin.compiled.fileURL(for: "Encoder.mlmodelc/weights/weight.bin").absoluteString,
            "https://huggingface.co/markstrom/pianissimo-sv-coreml/resolve/dd578628d1ae6577b4672221b99fff59112ff5b4/compiled/1.1.0/Encoder.mlmodelc/weights/weight.bin"
        )
        XCTAssertTrue(ModelPin.compiled.matches(Data(ManifestFixtures.compiled.utf8)))
    }

    func testAnyOtherManifestDoesNotMatchThePin() {
        XCTAssertFalse(ModelPin.compiled.matches(Data(ManifestFixtures.published.utf8)))
        XCTAssertFalse(ModelPin.packages.matches(Data((ManifestFixtures.published + " ").utf8)))
    }

    func testThePinnedCompiledReleaseIsValidOnlyFromMacOS26() throws {
        let release = try XCTUnwrap(ModelManifest.decode(Data(ManifestFixtures.compiled.utf8)).release(id: ModelManifest.pianissimoID))

        XCTAssertNoThrow(try release.validate(runningOn: .tahoe))
        XCTAssertThrowsError(try release.validate(runningOn: .sequoia))
        XCTAssertEqual(SemanticVersion(release.minimumOS?.macOS ?? ""), ModelPin.compiledMinimumSystem)
    }
}
