import os
import XCTest
@testable import SorlaCore

final class ModelInstallerTests: XCTestCase {
    private var modelsDirectory: URL!
    private var network: FakeModelNetwork!
    private var preparer: FakeModelPreparer!
    private let published = PublishedModelFixture()

    override func setUp() async throws {
        modelsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("sorla-installer-\(UUID().uuidString)")
        network = FakeModelNetwork()
        preparer = FakeModelPreparer()
        await published.publish(on: network)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: modelsDirectory)
    }

    private func installer(availableDiskSpace: Int64? = 10_000_000_000) -> ModelInstaller {
        ModelInstaller(
            modelsDirectory: modelsDirectory,
            manifestURL: PublishedModelFixture.manifestURL,
            filesBaseURL: PublishedModelFixture.filesBaseURL,
            network: network,
            preparer: preparer,
            availableDiskSpace: { _ in availableDiskSpace }
        )
    }

    private var staging: ModelStaging { ModelStaging(modelsDirectory: modelsDirectory, version: published.version) }

    func testFetchLatestRequestsOnlyTheManifest() async throws {
        let latest = try await installer().fetchLatest()

        XCTAssertEqual(latest.release, published.release)
        XCTAssertEqual(latest.manifestData, published.manifestData)
        let requests = await network.requests
        XCTAssertEqual(requests, [PublishedModelFixture.manifestURL])
    }

    func testFetchLatestWithoutPianissimoIsAnInvalidManifest() async throws {
        await network.serve(Data(#"{"schema":1,"models":[]}"#.utf8), at: PublishedModelFixture.manifestURL)

        await assertThrows(.invalidManifest) { _ = try await self.installer().fetchLatest() }
    }

    func testFetchLatestOfflineIsANetworkError() async throws {
        await network.fail(PublishedModelFixture.manifestURL)

        await assertThrows(.network) { _ = try await self.installer().fetchLatest() }
    }

    func testStagesACompleteModelFromTheVersionTag() async throws {
        let assembled = try await installer().stage(published.latest) { _ in }

        XCTAssertEqual(assembled.path, staging.assembledDirectory.path)
        let names = try FileManager.default.contentsOfDirectory(atPath: assembled.path).sorted()
        XCTAssertEqual(names, [
            "Decoder.mlmodelc", "Encoder.mlmodelc", "JointDecisionv3.mlmodelc", "LICENSE-and-attribution.txt",
            "Preprocessor.mlmodelc", "manifest.json", "parakeet_vocab.json",
        ])
        XCTAssertEqual(PianissimoModel.installedVersion(at: assembled), "1.1.0")
        XCTAssertTrue(PianissimoModel.hasRequiredFiles(at: assembled))
        let requests = Set(await network.requests)
        XCTAssertEqual(requests, Set(published.contents.keys.map(published.url(for:))))
        let compiled = await preparer.compiled.sorted()
        XCTAssertEqual(compiled, ["Decoder.mlpackage", "Encoder.mlpackage", "JointDecisionv3.mlpackage", "Preprocessor.mlpackage"])
        let selfTested = await preparer.selfTested
        XCTAssertEqual(selfTested.map(\.path), [assembled.path])
    }

    func testResumeDownloadsOnlyFilesThatDoNotVerify() async throws {
        let done = ["Encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin", "parakeet_vocab.json"]
        for path in done {
            try place(published.contents[path]!, at: staging.downloadLocation(for: path))
        }
        try place("truncat", at: staging.downloadLocation(for: "README.md"))

        _ = try await installer().stage(published.latest) { _ in }

        let requests = Set(await network.requests)
        let expected = published.contents.keys.filter { !done.contains($0) }.map(published.url(for:))
        XCTAssertEqual(requests, Set(expected))
    }

    func testACorruptDownloadFailsVerificationAndIsDiscarded() async throws {
        let path = "Encoder.mlpackage/Manifest.json"
        await network.serve(Data("tampered".utf8), at: published.url(for: path))

        await assertThrows(.verificationFailed(path: path)) { _ = try await self.installer().stage(self.published.latest) { _ in } }

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.downloadLocation(for: path).path))
        let selfTested = await preparer.selfTested
        XCTAssertTrue(selfTested.isEmpty)
    }

    func testInsufficientDiskSpaceFailsBeforeAnyDownload() async throws {
        let required = DiskSpace.required(forDownloadOf: published.release.totalSize)

        await assertThrows(.insufficientDiskSpace(required: required)) {
            _ = try await self.installer(availableDiskSpace: required - 1).stage(self.published.latest) { _ in }
        }

        let requests = await network.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testNetworkFailureKeepsWhatWasAlreadyDownloaded() async throws {
        await network.fail(published.url(for: "README.md"))

        await assertThrows(.network) { _ = try await self.installer().stage(self.published.latest) { _ in } }

        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.downloadLocation(for: "Decoder.mlpackage/Manifest.json").path))
    }

    func testSelfTestFailureDiscardsTheAssembledModelButKeepsDownloads() async throws {
        await preparer.failSelfTest()

        await assertThrows(.selfTestFailed) { _ = try await self.installer().stage(self.published.latest) { _ in } }

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.assembledDirectory.path))
        XCTAssertTrue(staging.filesNeedingDownload(published.files).isEmpty)
    }

    func testCompileFailureIsReported() async throws {
        await preparer.failCompile()

        await assertThrows(.compileFailed) { _ = try await self.installer().stage(self.published.latest) { _ in } }

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.assembledDirectory.path))
    }

    func testStagingForOtherVersionsIsCleanedUp() async throws {
        let stale = ModelStaging(modelsDirectory: modelsDirectory, version: "1.0.5")
        try place("old", at: stale.downloadLocation(for: "x"))

        _ = try await installer().stage(published.latest) { _ in }

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.directory.path))
    }

    func testReportsDownloadProgressThenPreparing() async throws {
        let recorder = ProgressRecorder()

        _ = try await installer().stage(published.latest) { recorder.record($0) }

        let events = recorder.events
        XCTAssertEqual(events.last, .preparing)
        guard case .downloading(let last) = events.dropLast().last else { return XCTFail("no download progress: \(events)") }
        XCTAssertEqual(last, 1, accuracy: 0.0001)
    }

    private func place(_ contents: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private func assertThrows(_ expected: ModelInstallError, file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ModelInstallError, expected, file: file, line: line)
        }
    }
}

extension PublishedModelFixture {
    var latest: PublishedModel { PublishedModel(release: release, manifestData: manifestData) }
}

final class ProgressRecorder: Sendable {
    private let storage = OSAllocatedUnfairLock<[ModelInstallProgress]>(initialState: [])

    func record(_ progress: ModelInstallProgress) {
        storage.withLock { $0.append(progress) }
    }

    var events: [ModelInstallProgress] { storage.withLock { $0 } }
}
