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

    func testRemoteURLUsesTheImmutableVersionTag() {
        let base = URL(string: "https://huggingface.co/markstrom/pianissimo-sv-coreml/resolve")!

        XCTAssertEqual(
            ModelStaging.remoteURL(base: base, version: "1.1.0", path: "Encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin").absoluteString,
            "https://huggingface.co/markstrom/pianissimo-sv-coreml/resolve/1.1.0/Encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin"
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

    static func sha256(_ contents: String) -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? Data(contents.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return (try? FileVerifier.sha256(of: url)) ?? ""
    }
}
