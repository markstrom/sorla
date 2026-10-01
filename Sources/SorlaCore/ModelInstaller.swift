import Foundation
import os

// Work nobody asked for stays off networks the Mac marks as costly: a phone's hotspot or Low Data Mode.
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

    public init(release: ModelRelease, manifestData: Data) {
        self.release = release
        self.manifestData = manifestData
    }
}

public struct ModelInstaller: Sendable {
    public let modelsDirectory: URL
    public let pin: ModelPin
    private let system: SemanticVersion
    private let network: ModelNetwork
    private let preparer: ModelPreparer
    private let placer: ModelFilePlacer
    private let availableDiskSpace: @Sendable (URL) -> Int64?
    private static let logger = Logger(subsystem: "com.sorla.app", category: "ModelInstaller")

    public init(
        modelsDirectory: URL,
        pin: ModelPin = .current,
        system: SemanticVersion = .runningSystem,
        network: ModelNetwork,
        preparer: ModelPreparer,
        placer: ModelFilePlacer = ModelFilePlacer(),
        availableDiskSpace: @escaping @Sendable (URL) -> Int64? = { DiskSpace.available(at: $0) }
    ) {
        self.modelsDirectory = modelsDirectory
        self.pin = pin
        self.system = system
        self.network = network
        self.preparer = preparer
        self.placer = placer
        self.availableDiskSpace = availableDiskSpace
    }

    // Fetches the pinned manifest; anything but exactly that file, valid for this Mac, is refused.
    public func fetchLatest(access: ModelNetworkAccess = .any) async throws -> PublishedModel {
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
        return PublishedModel(release: release, manifestData: data)
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
        let staging = ModelStaging(modelsDirectory: modelsDirectory, version: release.version)
        let fileManager = FileManager.default

        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        let required = DiskSpace.required(forDownloadOf: release.totalSize, format: format)
        guard DiskSpace.hasRoom(available: availableDiskSpace(modelsDirectory), forDownloadOf: release.totalSize, format: format) else {
            Self.logger.error("not enough disk space for model \(release.version, privacy: .public): \(required, privacy: .public) bytes needed")
            throw ModelInstallError.insufficientDiskSpace(required: required)
        }
        try? staging.removeOtherVersions()
        try? fileManager.removeItem(at: staging.assembledDirectory)

        try await download(release, into: staging, access: access, progress: progress)
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

    private func download(_ release: ModelRelease, into staging: ModelStaging, access: ModelNetworkAccess, progress: @escaping @Sendable (ModelInstallProgress) -> Void) async throws {
        let total = max(release.totalSize, 1)
        let pending = staging.filesNeedingDownload(release.files)
        var completed = total - (ModelRelease.checkedSum(pending.map(\.size)) ?? total)
        Self.logger.info("staging model \(release.version, privacy: .public): \(pending.count, privacy: .public) of \(release.files.count, privacy: .public) files to download, \(completed, privacy: .public) bytes already verified")
        progress(.downloading(fraction: Double(completed) / Double(total)))

        for file in pending {
            try Task.checkCancellation()
            let destination = staging.downloadLocation(for: file.path)
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
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
            guard FileVerifier.matches(destination, size: file.size, sha256: file.sha256) else {
                try? FileManager.default.removeItem(at: destination)
                Self.logger.error("verification failed: \(file.path, privacy: .public)")
                throw ModelInstallError.verificationFailed(path: file.path)
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
