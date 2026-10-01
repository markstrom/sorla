import Foundation
import os

// Automatic model updates use `.inexpensiveOnly`, which stays off networks the Mac marks as costly:
// a phone's hotspot or Low Data Mode. Everything else, including app updates, uses `.any`.
public enum ModelNetworkAccess: Equatable, Sendable {
    case any
    case inexpensiveOnly
}

public protocol ModelNetwork: Sendable {
    func data(from url: URL, access: ModelNetworkAccess) async throws -> Data
    // May continue a partial download left by an earlier attempt; the caller verifies the finished file.
    func download(from url: URL, to destination: URL, maxBytes: Int64, access: ModelNetworkAccess, progress: @escaping @Sendable (Int64) -> Void) async throws
}

public enum ModelNetworkError: Error, Equatable, Sendable {
    case httpStatus(Int)
    case tooLarge
    // Only for `.inexpensiveOnly`: the work waits for a later check instead of failing.
    case costlyNetwork
}

public protocol ModelPreparer: Sendable {
    func compile(package: URL, into destination: URL) async throws
    func selfTest(modelDirectory: URL) async throws
}

public enum ModelInstallProgress: Equatable, Sendable {
    case downloading(fraction: Double)
    case preparing
}

public struct PublishedModel: Equatable, Sendable {
    public let release: ModelRelease
    public let manifestData: Data
    // Where the manifest came from, so its files are fetched from the same folder.
    public let pin: ModelPin?

    public init(release: ModelRelease, manifestData: Data, pin: ModelPin? = nil) {
        self.release = release
        self.manifestData = manifestData
        self.pin = pin
    }
}

public struct ModelInstaller: Sendable {
    public let modelsDirectory: URL
    public let pins: ModelPins
    private let system: SemanticVersion
    private let network: ModelNetwork
    private let preparer: ModelPreparer
    private let placer: ModelFilePlacer
    private let availableDiskSpace: @Sendable (URL) -> Int64?
    private static let logger = Logger(subsystem: "com.sorla.app", category: "ModelInstaller")

    public init(
        modelsDirectory: URL,
        pins: ModelPins? = nil,
        system: SemanticVersion = .runningSystem,
        network: ModelNetwork,
        preparer: ModelPreparer,
        placer: ModelFilePlacer = ModelFilePlacer(),
        availableDiskSpace: @escaping @Sendable (URL) -> Int64? = { DiskSpace.available(at: $0) }
    ) {
        self.modelsDirectory = modelsDirectory
        self.pins = pins ?? .forSystem(system)
        self.system = system
        self.network = network
        self.preparer = preparer
        self.placer = placer
        self.availableDiskSpace = availableDiskSpace
    }

    // One release, without a fallback.
    public init(
        modelsDirectory: URL,
        pin: ModelPin,
        system: SemanticVersion = .runningSystem,
        network: ModelNetwork,
        preparer: ModelPreparer,
        placer: ModelFilePlacer = ModelFilePlacer(),
        availableDiskSpace: @escaping @Sendable (URL) -> Int64? = { DiskSpace.available(at: $0) }
    ) {
        self.init(
            modelsDirectory: modelsDirectory, pins: ModelPins(preferred: pin), system: system,
            network: network, preparer: preparer, placer: placer, availableDiskSpace: availableDiskSpace
        )
    }

    // The fallback once the preferred release has failed a first install on this macOS version.
    public var pin: ModelPin {
        guard let fallback = pins.fallback, preferredFailure.isRecorded(for: pins.preferred, system: system) else { return pins.preferred }
        return fallback
    }

    private var preferredFailure: PreferredModelFailure { PreferredModelFailure(modelsDirectory: modelsDirectory) }

    // After a first install of the preferred release couldn't be placed, assembled or self-tested, switches to the fallback.
    // Returns whether there is a fallback to install now; network, disk and verification errors never switch.
    public func fallBack(after error: Error) -> Bool {
        guard let fallback = pins.fallback, pin == pins.preferred else { return false }
        switch error as? ModelInstallError {
        case .installFailed, .selfTestFailed, .invalidManifest: break
        default: return false
        }
        // The record is what switches `pin`, so without it there is no fallback to install.
        do {
            try preferredFailure.record(pins.preferred, system: system)
        } catch {
            Self.logger.error("couldn't remember that model \(self.pins.preferred.version, privacy: .public) failed: \(ErrorSummary.of(error), privacy: .public)")
            return false
        }
        Self.logger.error("model \(self.pins.preferred.version, privacy: .public) can't be used on macOS \(self.system.description, privacy: .public); falling back to \(fallback.version, privacy: .public)")
        return true
    }

    // Fetches the pinned manifest; anything but exactly that file, valid for this Mac, is refused.
    public func fetchLatest(access: ModelNetworkAccess = .any) async throws -> PublishedModel {
        let pin = self.pin
        let data: Data
        Self.logger.info("fetching model manifest \(self.pin.version, privacy: .public)")
        do {
            data = try await network.data(from: pin.manifestURL, access: access)
        } catch {
            throw Self.installError(error)
        }
        guard pin.matches(data) else {
            Self.logger.error("model manifest doesn't match its pinned checksum")
            throw ModelInstallError.invalidManifest
        }
        guard let manifest = try? ModelManifest.decode(data),
              let release = manifest.release(id: ModelManifest.pianissimoID),
              release.version == pin.version
        else {
            Self.logger.error("model manifest couldn't be read")
            throw ModelInstallError.invalidManifest
        }
        do {
            try release.validate(runningOn: system)
        } catch {
            Self.logger.error("model manifest failed validation")
            throw error
        }
        Self.logger.info("model manifest: \(release.id, privacy: .public) \(release.version, privacy: .public) (\(release.format ?? "mlpackage", privacy: .public)), \(release.files.count, privacy: .public) files, \(release.totalSize, privacy: .public) bytes")
        return PublishedModel(release: release, manifestData: data, pin: pin)
    }

    // Downloads, verifies and prepares into staging, then self-tests; the installed model is never touched here.
    public func stage(_ published: PublishedModel, access: ModelNetworkAccess = .any, progress: @escaping @Sendable (ModelInstallProgress) -> Void) async throws -> URL {
        let release = published.release
        do {
            try release.validate(runningOn: system)
        } catch {
            Self.logger.error("model manifest failed validation")
            throw error
        }
        let format = release.modelFormat ?? .packages
        let pin = published.pin ?? self.pin
        let staging = ModelStaging(modelsDirectory: modelsDirectory, version: release.version)
        let fileManager = FileManager.default

        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        // Files the Mac already has come first, then what still needs downloading, and only then is other staging removed.
        seed(release, into: staging)
        let pending = staging.filesNeedingDownload(release.files)
        try? staging.removeOtherVersions()
        try? fileManager.removeItem(at: staging.assembledDirectory)

        let staged = release.totalSize - (ModelRelease.checkedSum(pending.map(\.size)) ?? release.totalSize)
        let required = DiskSpace.required(forDownloadOf: release.totalSize, alreadyStaged: staged, format: format)
        guard DiskSpace.hasRoom(available: availableDiskSpace(modelsDirectory), forDownloadOf: release.totalSize, alreadyStaged: staged, format: format) else {
            Self.logger.error("not enough disk space for model \(release.version, privacy: .public): \(required, privacy: .public) bytes needed")
            throw ModelInstallError.insufficientDiskSpace(required: required)
        }

        try await download(pending, of: release, from: pin, into: staging, access: access, progress: progress)
        Self.logger.info("all model files downloaded and verified")
        progress(.preparing)
        do {
            try await assemble(published, format: format, from: staging)
        } catch {
            try? fileManager.removeItem(at: staging.assembledDirectory)
            throw error
        }
        return staging.assembledDirectory
    }

    // Clones files the installed model or another version's downloads already hold, matched by size and SHA-256, never by path:
    // the compiled release lays its files out differently from the packages. Runs on the installer's background task.
    private func seed(_ release: ModelRelease, into staging: ModelStaging) {
        let fileManager = FileManager.default
        let wanted = release.files.filter { file in
            let size = (try? staging.downloadLocation(for: file.path).resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            return size != file.size
        }
        guard !wanted.isEmpty else { return }
        let wantedSizes = Set(wanted.map(\.size))
        let wantedHashes = Set(wanted.map(\.sha256))
        let sources = [ModelSwap(modelsDirectory: modelsDirectory).installed] + staging.otherVersionsDownloads
        var bySHA256: [String: URL] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        for source in sources {
            guard let files = fileManager.enumerator(at: source, includingPropertiesForKeys: keys) else { continue }
            for case let candidate as URL in files {
                guard let values = try? candidate.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, wantedSizes.contains(Int64(size)),
                      let hash = try? FileVerifier.sha256(of: candidate), wantedHashes.contains(hash), bySHA256[hash] == nil
                else { continue }
                bySHA256[hash] = candidate
            }
        }
        var seeded = 0
        var seededBytes: Int64 = 0
        for file in wanted {
            guard let source = bySHA256[file.sha256] else { continue }
            let destination = staging.downloadLocation(for: file.path)
            do {
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fileManager.removeItem(at: ModelStaging.partialLocation(for: destination))
                // A copy takes real space, so it is only made with room to spare.
                try placer.copy(source, to: destination) {
                    (availableDiskSpace(modelsDirectory) ?? 0) >= file.size + DiskSpace.margin(for: release.totalSize)
                }
                seeded += 1
                seededBytes += file.size
            } catch {
                Self.logger.info("couldn't reuse a local copy of \(file.path, privacy: .public): \(ErrorSummary.of(error), privacy: .public)")
            }
        }
        if seeded > 0 {
            Self.logger.info("reused \(seeded, privacy: .public) files (\(seededBytes, privacy: .public) bytes) the Mac already had")
        }
    }

    private func download(_ pending: [ModelFile], of release: ModelRelease, from pin: ModelPin, into staging: ModelStaging, access: ModelNetworkAccess, progress: @escaping @Sendable (ModelInstallProgress) -> Void) async throws {
        let total = max(release.totalSize, 1)
        var completed = total - (ModelRelease.checkedSum(pending.map(\.size)) ?? total)
        Self.logger.info("staging model \(release.version, privacy: .public): \(pending.count, privacy: .public) of \(release.files.count, privacy: .public) files to download, \(completed, privacy: .public) bytes already verified")
        progress(.downloading(fraction: Double(completed) / Double(total)))

        for file in pending {
            try Task.checkCancellation()
            let destination = staging.downloadLocation(for: file.path)
            let partial = ModelStaging.partialLocation(for: destination)
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            // A file continued from an earlier attempt may hold bad bytes from then, so it gets one fresh try before it counts as damaged.
            var resumed = FileManager.default.fileExists(atPath: partial.path)
            while true {
                let base = completed
                do {
                    try await network.download(from: pin.fileURL(for: file.path), to: destination, maxBytes: file.size, access: access) { received in
                        progress(.downloading(fraction: Double(base + min(received, file.size)) / Double(total)))
                    }
                } catch ModelNetworkError.tooLarge {
                    try? FileManager.default.removeItem(at: destination)
                    Self.logger.error("download exceeded its declared size: \(file.path, privacy: .public)")
                    throw ModelInstallError.verificationFailed(path: file.path)
                } catch {
                    throw Self.installError(error)
                }
                if FileVerifier.matches(destination, size: file.size, sha256: file.sha256) { break }
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.removeItem(at: partial)
                guard resumed else {
                    Self.logger.error("verification failed: \(file.path, privacy: .public)")
                    throw ModelInstallError.verificationFailed(path: file.path)
                }
                Self.logger.error("resumed download failed verification; starting \(file.path, privacy: .public) over")
                resumed = false
            }
            Self.logger.info("verified \(file.path, privacy: .public) (\(file.size, privacy: .public) bytes)")
            completed += file.size
            progress(.downloading(fraction: Double(completed) / Double(total)))
        }
    }

    private func assemble(_ published: PublishedModel, format: ModelFormat, from staging: ModelStaging) async throws {
        let fileManager = FileManager.default
        let assembled = staging.assembledDirectory
        try fileManager.createDirectory(at: assembled, withIntermediateDirectories: true)

        switch format {
        case .packages:
            try await compilePackages(of: published, from: staging, into: assembled)
        case .compiled:
            try placeCompiledModels(of: published, from: staging, into: assembled)
        }
        guard PianissimoModel.hasRequiredFiles(at: assembled) else { throw ModelInstallError.invalidManifest }

        do {
            try await preparer.selfTest(modelDirectory: assembled)
        } catch {
            Self.logger.error("model self-test failed: \(ErrorSummary.of(error), privacy: .public) \(String(describing: error), privacy: .private)")
            throw ModelInstallError.selfTestFailed
        }
        Self.logger.info("model self-test passed")
    }

    private func compilePackages(of published: PublishedModel, from staging: ModelStaging, into assembled: URL) async throws {
        let release = published.release
        for name in release.packageNames {
            do {
                try await preparer.compile(
                    package: staging.downloadsDirectory.appendingPathComponent("\(name).mlpackage"),
                    into: assembled.appendingPathComponent("\(name).mlmodelc")
                )
            } catch {
                Self.logger.error("compile failed: \(name, privacy: .public): \(ErrorSummary.of(error), privacy: .public) \(String(describing: error), privacy: .private)")
                throw ModelInstallError.compileFailed
            }
            Self.logger.info("compiled \(name, privacy: .public)")
        }
        do {
            for path in [ModelRelease.vocabularyPath, ModelRelease.licensePath] where release.files.contains(where: { $0.path == path }) {
                try FileManager.default.copyItem(at: staging.downloadLocation(for: path), to: assembled.appendingPathComponent(path))
            }
            try published.manifestData.write(to: assembled.appendingPathComponent("manifest.json"))
        } catch {
            Self.logger.error("couldn't copy model files: \(ErrorSummary.of(error), privacy: .public)")
            throw ModelInstallError.installFailed
        }
    }

    // The downloads already are the finished model: they are cloned into place, or moved where cloning isn't possible.
    private func placeCompiledModels(of published: PublishedModel, from staging: ModelStaging, into assembled: URL) throws {
        let release = published.release
        let items = release.compiledModelNames.map { "\($0).mlmodelc" }
            + [ModelRelease.vocabularyPath, ModelRelease.licensePath].filter { path in release.files.contains { $0.path == path } }
        do {
            for item in items {
                let placement = try placer.place(staging.downloadLocation(for: item), at: assembled.appendingPathComponent(item))
                Self.logger.info("placed \(item, privacy: .public) (\(String(describing: placement), privacy: .public))")
            }
            try published.manifestData.write(to: assembled.appendingPathComponent("manifest.json"))
        } catch {
            Self.logger.error("couldn't place model files: \(ErrorSummary.of(error), privacy: .public)")
            throw ModelInstallError.installFailed
        }
    }

    // Only transport failures mean "no connection"; server answers and local file errors get their own wording.
    static func installError(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if isCostlyNetworkRefusal(error) {
            logger.info("model download waits for a network that isn't marked as costly")
            return ModelNetworkError.costlyNetwork
        }
        logger.error("model download failed: \(ErrorSummary.of(error), privacy: .public)")
        switch error {
        case let urlError as URLError:
            switch urlError.code {
            case .cannotWriteToFile, .cannotCreateFile, .cannotMoveFile, .cannotOpenFile, .cannotCloseFile, .cannotRemoveFile:
                return ModelInstallError.diskWriteFailed
            case .badServerResponse:
                return ModelInstallError.serverUnavailable
            default:
                return ModelInstallError.network
            }
        case ModelNetworkError.httpStatus: return ModelInstallError.serverUnavailable
        case let installError as ModelInstallError: return installError
        default: return ModelInstallError.diskWriteFailed
        }
    }

    // URLSession refuses a request it may not send over an expensive or constrained network with this reason.
    static func isCostlyNetworkRefusal(_ error: Error) -> Bool {
        if case ModelNetworkError.costlyNetwork = error { return true }
        guard let reason = (error as? URLError)?.networkUnavailableReason else { return false }
        return reason == .expensive || reason == .constrained
    }
}
