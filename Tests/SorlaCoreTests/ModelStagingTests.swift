import CryptoKit
import XCTest
@testable import SorlaCore

final class ModelStagingTests: XCTestCase {
    private var modelsDirectory: URL!

    override func setUpWithError() throws {
        modelsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("sorla-staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: modelsDirectory)
    }

    func testPlansPathsInsideTheModelsDirectory() {
        let staging = ModelStaging(modelsDirectory: modelsDirectory, version: "1.1.0")

        XCTAssertEqual(staging.directory.path, modelsDirectory.appendingPathComponent(".staging/pianissimo-sv-1.1.0").path)
        XCTAssertEqual(staging.downloadsDirectory.path, staging.directory.appendingPathComponent("download").path)
        XCTAssertEqual(staging.assembledDirectory.path, staging.directory.appendingPathComponent("model").path)
        XCTAssertEqual(
            staging.downloadLocation(for: "Encoder.mlpackage/Manifest.json").path,
            staging.downloadsDirectory.appendingPathComponent("Encoder.mlpackage/Manifest.json").path
        )
    }

    func testEveryFileNeedsDownloadingIntoAnEmptyStagingDirectory() {
        let staging = ModelStaging(modelsDirectory: modelsDirectory, version: "1.1.0")
        let files = [file("a.txt", "alpha"), file("b/c.txt", "beta")]

        XCTAssertEqual(staging.filesNeedingDownload(files), files)
    }

    func testResumeSkipsFilesThatAlreadyVerify() throws {
        let staging = ModelStaging(modelsDirectory: modelsDirectory, version: "1.1.0")
        let done = file("b/c.txt", "beta")
        let partial = file("a.txt", "alpha")
        try place("beta", at: staging.downloadLocation(for: done.path))
        try place("alp", at: staging.downloadLocation(for: partial.path))

        XCTAssertEqual(staging.filesNeedingDownload([partial, done]), [partial])
    }

    func testRemovingOtherVersionsKeepsThisOne() throws {
        let current = ModelStaging(modelsDirectory: modelsDirectory, version: "1.1.0")
        let stale = ModelStaging(modelsDirectory: modelsDirectory, version: "1.0.5")
        try place("x", at: current.downloadLocation(for: "x"))
        try place("y", at: stale.downloadLocation(for: "y"))

        try current.removeOtherVersions()

        XCTAssertTrue(FileManager.default.fileExists(atPath: current.downloadLocation(for: "x").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.directory.path))
    }

    func testRemoveAllDeletesTheVersionAndTheEmptyRoot() throws {
        let staging = ModelStaging(modelsDirectory: modelsDirectory, version: "1.0.0")
        try place("x", at: staging.downloadLocation(for: "Encoder.mlpackage/Manifest.json"))

        try staging.removeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.root.path))
    }

    func testRemoveAllKeepsTheRootWhileOtherVersionsRemain() throws {
        let staging = ModelStaging(modelsDirectory: modelsDirectory, version: "1.0.0")
        let other = ModelStaging(modelsDirectory: modelsDirectory, version: "1.1.0")
        try place("x", at: staging.downloadLocation(for: "x"))
        try place("y", at: other.downloadLocation(for: "y"))

        try staging.removeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.directory.path))
    }

    func testStaleStagingUpToTheInstalledVersionIsRemoved() throws {
        for version in ["0.9.0", "1.0.0", "1.1.0"] {
            try place("x", at: ModelStaging(modelsDirectory: modelsDirectory, version: version).downloadLocation(for: "x"))
        }

        let removed = ModelStaging.removeStale(in: modelsDirectory, installedVersion: "1.0.0")

        XCTAssertEqual(removed.sorted(), ["pianissimo-sv-0.9.0", "pianissimo-sv-1.0.0"])
        let remaining = try FileManager.default.contentsOfDirectory(atPath: ModelStaging(modelsDirectory: modelsDirectory, version: "x").root.path)
        XCTAssertEqual(remaining, ["pianissimo-sv-1.1.0"])
    }

    func testStaleStagingCleanupRemovesTheEmptyRoot() throws {
        let staging = ModelStaging(modelsDirectory: modelsDirectory, version: "1.0.0")
        try place("x", at: staging.downloadLocation(for: "x"))

        _ = ModelStaging.removeStale(in: modelsDirectory, installedVersion: "1.0.0")

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.root.path))
    }

    func testStaleStagingCleanupWithoutAKnownVersionKeepsEverything() throws {
        let staging = ModelStaging(modelsDirectory: modelsDirectory, version: "1.0.0")
        try place("x", at: staging.downloadLocation(for: "x"))

        XCTAssertEqual(ModelStaging.removeStale(in: modelsDirectory, installedVersion: nil), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.directory.path))
    }

    func testDiskSpaceRequirementSaturatesInsteadOfOverflowing() {
        XCTAssertEqual(DiskSpace.required(forDownloadOf: .max), .max)
    }

    func testRemovingEverythingClearsAllVersionsAndTheRoot() throws {
        for version in ["1.0.0", "2.0.0"] {
            try FileManager.default.createDirectory(
                at: ModelStaging(modelsDirectory: modelsDirectory, version: version).downloadsDirectory,
                withIntermediateDirectories: true
            )
        }

        let removed = ModelStaging.removeEverything(in: modelsDirectory)

        XCTAssertEqual(removed.sorted(), ["pianissimo-sv-1.0.0", "pianissimo-sv-2.0.0"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent(ModelStaging.rootName).path))
    }

    func testDiskSpaceNeedsTwiceTheDownload() {
        XCTAssertEqual(DiskSpace.required(forDownloadOf: 688_257_471), 1_376_514_942)
        XCTAssertTrue(DiskSpace.hasRoom(available: 1_376_514_942, forDownloadOf: 688_257_471))
        XCTAssertFalse(DiskSpace.hasRoom(available: 1_376_514_941, forDownloadOf: 688_257_471))
        XCTAssertFalse(DiskSpace.hasRoom(available: nil, forDownloadOf: 1))
    }

    func testCompiledModelsNeedRoomForOneCopyAndAMargin() {
        XCTAssertEqual(DiskSpace.margin(for: 688_595_324), 200_000_000)
        XCTAssertEqual(DiskSpace.margin(for: 5_000_000_000), 500_000_000)
        XCTAssertEqual(DiskSpace.required(forDownloadOf: 688_595_324, format: .compiled), 888_595_324)
        XCTAssertTrue(DiskSpace.hasRoom(available: 888_595_324, forDownloadOf: 688_595_324, format: .compiled))
        XCTAssertFalse(DiskSpace.hasRoom(available: 888_595_323, forDownloadOf: 688_595_324, format: .compiled))
        XCTAssertEqual(DiskSpace.required(forDownloadOf: .max, format: .compiled), .max)
    }

    func testBytesAlreadyStagedAreNotCountedAgain() {
        XCTAssertEqual(DiskSpace.required(forDownloadOf: 688_595_324, alreadyStaged: 687_500_000, format: .compiled), 201_095_324)
        XCTAssertEqual(DiskSpace.required(forDownloadOf: 688_257_471, alreadyStaged: 688_257_471), 688_257_471)
        XCTAssertEqual(DiskSpace.required(forDownloadOf: 100, alreadyStaged: 500, format: .compiled), 200_000_000)
        XCTAssertEqual(DiskSpace.required(forDownloadOf: 100, alreadyStaged: -5), 200)
    }

    func testCopyingClonesAndLeavesTheSourceInPlace() throws {
        let source = modelsDirectory.appendingPathComponent("installed/weight.bin")
        let destination = modelsDirectory.appendingPathComponent("staging/weight.bin")
        try place("weights", at: source)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        XCTAssertEqual(try ModelFilePlacer().copy(source, to: destination), .cloned)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "weights")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCopyingFallsBackToARealCopyOnlyWhenAllowed() throws {
        let source = modelsDirectory.appendingPathComponent("installed/weight.bin")
        let destination = modelsDirectory.appendingPathComponent("staging/weight.bin")
        try place("weights", at: source)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let placer = ModelFilePlacer { _, _ in throw POSIXError(.ENOTSUP) }

        XCTAssertThrowsError(try placer.copy(source, to: destination) { false })
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        XCTAssertEqual(try placer.copy(source, to: destination) { true }, .copied)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "weights")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testPlacingAFolderClonesItAndKeepsTheDownload() throws {
        let source = modelsDirectory.appendingPathComponent("download/Encoder.mlmodelc")
        let destination = modelsDirectory.appendingPathComponent("model/Encoder.mlmodelc")
        try place("weights", at: source.appendingPathComponent("weights/weight.bin"))
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let placement = try ModelFilePlacer().place(source, at: destination)

        // The test folder lives on the startup disk, which is APFS on every supported Mac.
        XCTAssertEqual(placement, .cloned)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("weights/weight.bin"), encoding: .utf8), "weights")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("weights/weight.bin").path))
    }

    func testPlacingFallsBackToAMoveWhenCloningFails() throws {
        let source = modelsDirectory.appendingPathComponent("download/Decoder.mlmodelc")
        let destination = modelsDirectory.appendingPathComponent("model/Decoder.mlmodelc")
        try place("weights", at: source.appendingPathComponent("weights/weight.bin"))
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let placer = ModelFilePlacer { _, destination in
            // A clone that fails halfway must not leave anything in the move's way.
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            throw POSIXError(.ENOTSUP)
        }

        let placement = try placer.place(source, at: destination)

        XCTAssertEqual(placement, .moved)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("weights/weight.bin"), encoding: .utf8), "weights")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testPlacingReplacesWhatAnEarlierAttemptLeftBehind() throws {
        let source = modelsDirectory.appendingPathComponent("download/parakeet_vocab.json")
        let destination = modelsDirectory.appendingPathComponent("model/parakeet_vocab.json")
        try place("new", at: source)
        try place("old", at: destination)

        try ModelFilePlacer().place(source, at: destination)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "new")
    }

    func testAvailableDiskSpaceIsReportedForARealVolume() throws {
        XCTAssertGreaterThan(try XCTUnwrap(DiskSpace.available(at: modelsDirectory)), 0)
    }

    private func file(_ path: String, _ contents: String) -> ModelFile {
        ModelFile(path: path, size: Int64(contents.utf8.count), sha256: Self.sha256(contents))
    }

    private func place(_ contents: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ contents: String) -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? Data(contents.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return (try? FileVerifier.sha256(of: url)) ?? ""
    }
}
