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

    private func installer(
        availableDiskSpace: Int64? = 10_000_000_000,
        pin: ModelPin? = nil,
        system: SemanticVersion = .sequoia,
        placer: ModelFilePlacer = ModelFilePlacer()
    ) -> ModelInstaller {
        ModelInstaller(
            modelsDirectory: modelsDirectory,
            pin: pin ?? published.pin,
            system: system,
            network: network,
            preparer: preparer,
            placer: placer,
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
        let empty = Data(#"{"schema":1,"models":[]}"#.utf8)
        await network.serve(empty, at: PublishedModelFixture.manifestURL)
        let pin = ModelPin(version: "1.1.0", manifestURL: PublishedModelFixture.manifestURL, manifestSHA256: ModelStagingTests.sha256(of: empty))

        await assertThrows(.invalidManifest) { _ = try await self.installer(pin: pin).fetchLatest() }
    }

    func testFetchLatestRefusesAManifestThatDoesNotMatchThePin() async throws {
        await network.serve(PublishedModelFixture(version: "1.2.0").manifestData, at: PublishedModelFixture.manifestURL)

        await assertThrows(.invalidManifest) { _ = try await self.installer().fetchLatest() }
    }

    func testFetchLatestRefusesAPinnedManifestOfAnotherVersion() async throws {
        let pin = ModelPin(version: "1.2.0", manifestURL: published.pin.manifestURL, manifestSHA256: published.pin.manifestSHA256)

        await assertThrows(.invalidManifest) { _ = try await self.installer(pin: pin).fetchLatest() }
    }

    func testFetchLatestRefusesACompiledReleaseOnAnOlderMacOS() async throws {
        let compiled = PublishedModelFixture(version: "1.1.0", format: .compiled)
        await compiled.publish(on: network)

        await assertThrows(.invalidManifest) { _ = try await self.installer(pin: compiled.pin, system: .sequoia).fetchLatest() }
        let latest = try await installer(pin: compiled.pin, system: .tahoe).fetchLatest()
        XCTAssertEqual(latest.release, compiled.release)
    }

    func testFetchLatestPassesTheNetworkAccessOn() async throws {
        _ = try await installer().fetchLatest(access: .inexpensiveOnly)
        _ = try await installer().stage(published.latest, access: .inexpensiveOnly) { _ in }

        let accesses = await network.accesses
        XCTAssertEqual(accesses.count, published.files.count + 1)
        XCTAssertTrue(accesses.values.allSatisfy { $0 == .inexpensiveOnly })
    }

    func testACostlyNetworkStopsWorkNobodyAskedForButNotTheUsersOwn() async throws {
        await network.useCostlyNetwork()

        do {
            _ = try await installer().stage(published.latest, access: .inexpensiveOnly) { _ in }
            XCTFail("staged over a costly network")
        } catch {
            XCTAssertEqual(error as? ModelNetworkError, .costlyNetwork)
        }
        _ = try await installer().stage(published.latest, access: .any) { _ in }
    }

    func testCostlyNetworkRefusalsAreToldApartFromBeingOffline() {
        for reason in [URLError.NetworkUnavailableReason.expensive, .constrained] {
            let refusal = URLError(.notConnectedToInternet, userInfo: [NSURLErrorNetworkUnavailableReasonKey: reason.rawValue])
            XCTAssertTrue(ModelInstaller.isCostlyNetworkRefusal(refusal), "\(reason)")
            XCTAssertEqual(ModelInstaller.installError(refusal) as? ModelNetworkError, .costlyNetwork)
        }
        XCTAssertFalse(ModelInstaller.isCostlyNetworkRefusal(URLError(.notConnectedToInternet)))
        XCTAssertEqual(ModelInstaller.installError(URLError(.notConnectedToInternet)) as? ModelInstallError, .network)
    }

    func testStagesAPrecompiledReleaseWithoutCompiling() async throws {
        let compiled = PublishedModelFixture(version: "1.1.0", format: .compiled)
        await compiled.publish(on: network)
        let installer = installer(pin: compiled.pin, system: .tahoe)

        let latest = try await installer.fetchLatest()
        let assembled = try await installer.stage(latest) { _ in }

        XCTAssertEqual(assembled.path, staging.assembledDirectory.path)
        let names = try FileManager.default.contentsOfDirectory(atPath: assembled.path).sorted()
        XCTAssertEqual(names, [
            "Decoder.mlmodelc", "Encoder.mlmodelc", "JointDecisionv3.mlmodelc", "LICENSE-and-attribution.txt",
            "Preprocessor.mlmodelc", "manifest.json", "parakeet_vocab.json",
        ])
        let weights = try String(contentsOf: assembled.appendingPathComponent("Encoder.mlmodelc/weights/weight.bin"), encoding: .utf8)
        XCTAssertEqual(weights, compiled.contents["Encoder.mlmodelc/weights/weight.bin"])
        XCTAssertEqual(try Data(contentsOf: assembled.appendingPathComponent("manifest.json")), compiled.manifestData)
        XCTAssertEqual(PianissimoModel.installedVersion(at: assembled), "1.1.0")
        XCTAssertTrue(PianissimoModel.hasRequiredFiles(at: assembled))
        let requests = Set(await network.requests)
        XCTAssertEqual(requests, Set(compiled.contents.keys.map(compiled.url(for:)) + [PublishedModelFixture.compiledManifestURL]))
        XCTAssertTrue(requests.allSatisfy { $0.absoluteString.hasPrefix("https://models.test/pianissimo/resolve/3d4e5f/compiled/") })
        let compiledPackages = await preparer.compiled
        XCTAssertEqual(compiledPackages, [])
        let selfTested = await preparer.selfTested
        XCTAssertEqual(selfTested.map(\.path), [assembled.path])
        // Cloned, so the verified downloads are still there for a retry.
        XCTAssertTrue(staging.filesNeedingDownload(compiled.files).isEmpty)
    }

    func testAPrecompiledReleaseIsMovedIntoPlaceWhereItCannotBeCloned() async throws {
        let compiled = PublishedModelFixture(version: "1.1.0", format: .compiled)
        await compiled.publish(on: network)
        let placer = ModelFilePlacer { _, _ in throw POSIXError(.ENOTSUP) }

        let assembled = try await installer(pin: compiled.pin, system: .tahoe, placer: placer).stage(compiled.latest) { _ in }

        XCTAssertTrue(PianissimoModel.hasRequiredFiles(at: assembled))
        let weights = try String(contentsOf: assembled.appendingPathComponent("Encoder.mlmodelc/weights/weight.bin"), encoding: .utf8)
        XCTAssertEqual(weights, compiled.contents["Encoder.mlmodelc/weights/weight.bin"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.downloadLocation(for: "Encoder.mlmodelc").path))
        let compiledPackages = await preparer.compiled
        XCTAssertEqual(compiledPackages, [])
    }

    func testAPrecompiledReleaseNeedsRoomForOneCopy() async throws {
        let compiled = PublishedModelFixture(version: "1.1.0", format: .compiled)
        await compiled.publish(on: network)
        let total = compiled.release.totalSize

        await assertThrows(.insufficientDiskSpace(required: total)) {
            _ = try await self.installer(availableDiskSpace: total - 1, pin: compiled.pin, system: .tahoe).stage(compiled.latest) { _ in }
        }
        let requests = await network.requests
        XCTAssertTrue(requests.isEmpty)

        _ = try await installer(availableDiskSpace: total, pin: compiled.pin, system: .tahoe).stage(compiled.latest) { _ in }
    }

    func testAPrecompiledReleaseIsNotStagedOnAnOlderMacOS() async throws {
        let compiled = PublishedModelFixture(version: "1.1.0", format: .compiled)
        await compiled.publish(on: network)

        await assertThrows(.invalidManifest) {
            _ = try await self.installer(pin: compiled.pin, system: .sequoia).stage(compiled.latest) { _ in }
        }
        let requests = await network.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testAPrecompiledReleaseThatFailsItsSelfTestKeepsTheVerifiedDownloads() async throws {
        let compiled = PublishedModelFixture(version: "1.1.0", format: .compiled)
        await compiled.publish(on: network)
        await preparer.failSelfTest()

        await assertThrows(.selfTestFailed) {
            _ = try await self.installer(pin: compiled.pin, system: .tahoe).stage(compiled.latest) { _ in }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.assembledDirectory.path))
        XCTAssertTrue(staging.filesNeedingDownload(compiled.files).isEmpty)
    }

    func testFetchLatestOfflineIsANetworkError() async throws {
        await network.fail(PublishedModelFixture.manifestURL)

        await assertThrows(.network) { _ = try await self.installer().fetchLatest() }
    }

    func testStagesAPackageReleaseByCompilingIt() async throws {
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

    func testAServerErrorIsNotReportedAsAMissingConnection() async throws {
        await network.fail(published.url(for: "README.md"), with: ModelNetworkError.httpStatus(404))

        await assertThrows(.serverUnavailable) { _ = try await self.installer().stage(self.published.latest) { _ in } }
    }

    func testAManifestServerErrorIsNotReportedAsAMissingConnection() async throws {
        await network.fail(PublishedModelFixture.manifestURL, with: ModelNetworkError.httpStatus(503))

        await assertThrows(.serverUnavailable) { _ = try await self.installer().fetchLatest() }
    }

    func testAFileErrorWhileSavingADownloadIsADiskProblem() async throws {
        await network.fail(published.url(for: "README.md"), with: CocoaError(.fileWriteOutOfSpace))

        await assertThrows(.diskWriteFailed) { _ = try await self.installer().stage(self.published.latest) { _ in } }
    }

    func testURLErrorsAreSortedIntoDiskServerAndNetworkProblems() {
        let disk: [URLError.Code] = [.cannotWriteToFile, .cannotCreateFile, .cannotMoveFile, .cannotOpenFile, .cannotCloseFile, .cannotRemoveFile]
        for code in disk {
            XCTAssertEqual(ModelInstaller.installError(URLError(code)) as? ModelInstallError, .diskWriteFailed, "\(code)")
        }
        XCTAssertEqual(ModelInstaller.installError(URLError(.badServerResponse)) as? ModelInstallError, .serverUnavailable)
        for code in [URLError.Code.notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotFindHost] {
            XCTAssertEqual(ModelInstaller.installError(URLError(code)) as? ModelInstallError, .network, "\(code)")
        }
    }

    func testAURLSessionDiskErrorWhileDownloadingIsADiskProblem() async throws {
        await network.fail(published.url(for: "README.md"), with: URLError(.cannotWriteToFile))

        await assertThrows(.diskWriteFailed) { _ = try await self.installer().stage(self.published.latest) { _ in } }
    }

    func testEachDownloadIsCappedAtItsDeclaredSize() async throws {
        _ = try await installer().stage(published.latest) { _ in }

        let limits = await network.downloadLimits
        for file in published.files {
            XCTAssertEqual(limits[published.url(for: file.path)], file.size, file.path)
        }
    }

    func testAnOversizedDownloadIsRejectedAndDiscarded() async throws {
        let path = "README.md"
        await network.serve(Data(String(repeating: "x", count: 10_000).utf8), at: published.url(for: path))

        await assertThrows(.verificationFailed(path: path)) { _ = try await self.installer().stage(self.published.latest) { _ in } }

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.downloadLocation(for: path).path))
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
