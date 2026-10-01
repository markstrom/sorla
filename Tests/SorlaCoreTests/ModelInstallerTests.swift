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

    func testAResumedFileThatFailsVerificationIsDownloadedOnceMoreFromTheStart() async throws {
        let path = "Encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin"
        try place("XXXX", at: ModelStaging.partialLocation(for: staging.downloadLocation(for: path)))

        _ = try await installer().stage(published.latest) { _ in }

        let attempts = await network.requests.filter { $0 == self.published.url(for: path) }
        XCTAssertEqual(attempts.count, 2)
        let resumed = await network.resumed
        XCTAssertEqual(resumed, [published.url(for: path)])
        XCTAssertTrue(staging.filesNeedingDownload(published.files).isEmpty)
    }

    func testAResumedFileThatFailsAgainFromTheStartIsDamaged() async throws {
        let path = "Encoder.mlpackage/Manifest.json"
        await network.serve(Data("ENC".utf8), at: published.url(for: path))
        try place("en", at: ModelStaging.partialLocation(for: staging.downloadLocation(for: path)))

        await assertThrows(.verificationFailed(path: path)) { _ = try await self.installer().stage(self.published.latest) { _ in } }

        let attempts = await network.requests.filter { $0 == self.published.url(for: path) }
        XCTAssertEqual(attempts.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ModelStaging.partialLocation(for: staging.downloadLocation(for: path)).path))
    }

    func testFilesTheMacAlreadyHasAreReusedByChecksumWhateverTheirPath() async throws {
        let compiled = PublishedModelFixture(version: "1.1.0", format: .compiled)
        await compiled.publish(on: network)
        let installed = ModelSwap(modelsDirectory: modelsDirectory).installed
        // The installed 1.0.0 holds the small weights and the vocabulary; an older version's packages hold the encoder weights.
        try place(compiled.contents["Decoder.mlmodelc/weights/weight.bin"]!, at: installed.appendingPathComponent("Decoder.mlmodelc/weights/weight.bin"))
        try place(compiled.contents["parakeet_vocab.json"]!, at: installed.appendingPathComponent("parakeet_vocab.json"))
        let older = ModelStaging(modelsDirectory: modelsDirectory, version: "1.0.0")
        try place(compiled.contents["Encoder.mlmodelc/weights/weight.bin"]!, at: older.downloadLocation(for: "Encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin"))

        _ = try await installer(pin: compiled.pin, system: .tahoe).stage(compiled.latest) { _ in }

        let downloaded = Set(await network.requests)
        let expected = compiled.contents.keys.filter { !$0.contains("weights/") && $0 != "parakeet_vocab.json" }.map(compiled.url(for:))
        XCTAssertEqual(downloaded, Set(expected))
        XCTAssertTrue(staging.filesNeedingDownload(compiled.files).isEmpty)
        // The installed model is left as it was, and other versions' downloads go once they have been used.
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent("Decoder.mlmodelc/weights/weight.bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: older.directory.path))
    }

    func testAFileOfTheRightSizeButOtherContentIsNotReused() async throws {
        let compiled = PublishedModelFixture(version: "1.1.0", format: .compiled)
        await compiled.publish(on: network)
        let path = "Encoder.mlmodelc/weights/weight.bin"
        try place(String(repeating: "x", count: compiled.contents[path]!.utf8.count), at: ModelSwap(modelsDirectory: modelsDirectory).installed.appendingPathComponent(path))

        _ = try await installer(pin: compiled.pin, system: .tahoe).stage(compiled.latest) { _ in }

        let downloaded = await network.requests
        XCTAssertTrue(downloaded.contains(compiled.url(for: path)))
    }

    func testReusedFilesCountTowardsTheDiskCheck() async throws {
        let compiled = PublishedModelFixture(version: "1.1.0", format: .compiled)
        await compiled.publish(on: network)
        let path = "Encoder.mlmodelc/weights/weight.bin"
        try place(compiled.contents[path]!, at: ModelSwap(modelsDirectory: modelsDirectory).installed.appendingPathComponent(path))
        let remaining = compiled.release.totalSize - Int64(compiled.contents[path]!.utf8.count)
        let required = remaining + DiskSpace.margin(for: compiled.release.totalSize)

        await assertThrows(.insufficientDiskSpace(required: required)) {
            _ = try await self.installer(availableDiskSpace: required - 1, pin: compiled.pin, system: .tahoe).stage(compiled.latest) { _ in }
        }
    }

    func testOnlyAFirstInstallOfThePreferredReleaseThatCannotBeUsedFallsBack() {
        let compiled = PublishedModelFixture(version: "1.1.0", format: .compiled)
        let pins = ModelPins(preferred: compiled.pin, fallback: published.pin)
        let installer = ModelInstaller(modelsDirectory: modelsDirectory, pins: pins, system: .tahoe, network: network, preparer: preparer)

        XCTAssertEqual(installer.pin, compiled.pin)
        for error: Error in [ModelInstallError.network, ModelInstallError.verificationFailed(path: "x"), ModelInstallError.insufficientDiskSpace(required: 1), CancellationError()] {
            XCTAssertFalse(installer.fallBack(after: error), "\(error)")
        }
        XCTAssertEqual(installer.pin, compiled.pin)

        XCTAssertTrue(installer.fallBack(after: ModelInstallError.selfTestFailed))
        XCTAssertEqual(installer.pin, published.pin)
        XCTAssertFalse(installer.fallBack(after: ModelInstallError.selfTestFailed), "there's nothing further to fall back to")

        // Remembered for this release on this macOS version only.
        let sameMac = ModelInstaller(modelsDirectory: modelsDirectory, pins: pins, system: .tahoe, network: network, preparer: preparer)
        XCTAssertEqual(sameMac.pin, published.pin)
        let updatedMac = ModelInstaller(modelsDirectory: modelsDirectory, pins: pins, system: SemanticVersion(major: 26, minor: 0, patch: 1), network: network, preparer: preparer)
        XCTAssertEqual(updatedMac.pin, compiled.pin)
    }

    func testAPlacementFailureCountsAsAReleaseThatCannotBeUsed() {
        let compiled = PublishedModelFixture(version: "1.1.0", format: .compiled)
        let installer = ModelInstaller(
            modelsDirectory: modelsDirectory, pins: ModelPins(preferred: compiled.pin, fallback: published.pin),
            system: .tahoe, network: network, preparer: preparer
        )

        XCTAssertTrue(installer.fallBack(after: ModelInstallError.installFailed))
    }

    func testASingleReleaseHasNoFallback() {
        XCTAssertFalse(installer().fallBack(after: ModelInstallError.selfTestFailed))
        XCTAssertEqual(installer().pin, published.pin)
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

    func testAPrecompiledReleaseNeedsRoomForOneCopyAndAMargin() async throws {
        let compiled = PublishedModelFixture(version: "1.1.0", format: .compiled)
        await compiled.publish(on: network)
        let required = compiled.release.totalSize + DiskSpace.margin(for: compiled.release.totalSize)

        await assertThrows(.insufficientDiskSpace(required: required)) {
            _ = try await self.installer(availableDiskSpace: required - 1, pin: compiled.pin, system: .tahoe).stage(compiled.latest) { _ in }
        }
        let requests = await network.requests
        XCTAssertTrue(requests.isEmpty)

        _ = try await installer(availableDiskSpace: required, pin: compiled.pin, system: .tahoe).stage(compiled.latest) { _ in }
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
        let attempts = await network.requests.filter { $0 == self.published.url(for: path) }
        XCTAssertEqual(attempts.count, 1, "a fresh download isn't fetched again")
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
