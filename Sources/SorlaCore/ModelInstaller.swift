import Foundation
import os

public protocol ModelNetwork: Sendable {
    func data(from url: URL) async throws -> Data
    func download(from url: URL, to destination: URL, maxBytes: Int64, progress: @escaping @Sendable (Int64) -> Void) async throws
}

public enum ModelNetworkError: Error, Equatable, Sendable {
    case httpStatus(Int)
    case tooLarge
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
    public static let manifestURL = URL(string: "https://huggingface.co/markstrom/pianissimo-sv-coreml/resolve/main/manifest.json")!
    public static let filesBaseURL = URL(string: "https://huggingface.co/markstrom/pianissimo-sv-coreml/resolve")!

    public let modelsDirectory: URL
    public let manifestURL: URL
    public let filesBaseURL: URL
    private let network: ModelNetwork
    private let preparer: ModelPreparer
    private let availableDiskSpace: @Sendable (URL) -> Int64?
    private static let logger = Logger(subsystem: "com.sorla.app", category: "ModelInstaller")

    public init(
        modelsDirectory: URL,
        manifestURL: URL = ModelInstaller.manifestURL,
        filesBaseURL: URL = ModelInstaller.filesBaseURL,
        network: ModelNetwork,
        preparer: ModelPreparer,
        availableDiskSpace: @escaping @Sendable (URL) -> Int64? = { DiskSpace.available(at: $0) }
    ) {
        self.modelsDirectory = modelsDirectory
        self.manifestURL = manifestURL
        self.filesBaseURL = filesBaseURL
        self.network = network
        self.preparer = preparer
        self.availableDiskSpace = availableDiskSpace
    }

    public func fetchLatest() async throws -> PublishedModel {
        let data: Data
        Self.logger.info("fetching model manifest")
        do {
            data = try await network.data(from: manifestURL)
        } catch {
            throw Self.installError(error)
        }
        guard let manifest = try? ModelManifest.decode(data),
              let release = manifest.release(id: ModelManifest.pianissimoID)
        else {
            Self.logger.error("model manifest couldn't be read")
            throw ModelInstallError.invalidManifest
        }
        Self.logger.info("model manifest: \(release.id, privacy: .public) \(release.version, privacy: .public), \(release.files.count, privacy: .public) files, \(release.totalSize, privacy: .public) bytes")
        return PublishedModel(release: release, manifestData: data)
    }

    // Downloads, verifies, compiles and self-tests into staging; the installed model is never touched here.
    public func stage(_ published: PublishedModel, progress: @escaping @Sendable (ModelInstallProgress) -> Void) async throws -> URL {
        let release = published.release
        do {
            try release.validate()
        } catch {
            Self.logger.error("model manifest failed validation")
            throw error
        }
        let staging = ModelStaging(modelsDirectory: modelsDirectory, version: release.version)
        let fileManager = FileManager.default

        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        guard DiskSpace.hasRoom(available: availableDiskSpace(modelsDirectory), forDownloadOf: release.totalSize) else {
            Self.logger.error("not enough disk space for model \(release.version, privacy: .public): \(DiskSpace.required(forDownloadOf: release.totalSize), privacy: .public) bytes needed")
            throw ModelInstallError.insufficientDiskSpace(required: DiskSpace.required(forDownloadOf: release.totalSize))
        }
        try? staging.removeOtherVersions()
        try? fileManager.removeItem(at: staging.assembledDirectory)

        try await download(release, into: staging, progress: progress)
        Self.logger.info("all model files downloaded and verified")
        progress(.preparing)
        do {
            try await assemble(published, from: staging)
        } catch {
            try? fileManager.removeItem(at: staging.assembledDirectory)
            throw error
        }
        return staging.assembledDirectory
    }

    private func download(_ release: ModelRelease, into staging: ModelStaging, progress: @escaping @Sendable (ModelInstallProgress) -> Void) async throws {
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
                let url = ModelStaging.remoteURL(base: filesBaseURL, version: release.version, path: file.path)
                try await network.download(from: url, to: destination, maxBytes: file.size) { received in
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

    private func assemble(_ published: PublishedModel, from staging: ModelStaging) async throws {
        let release = published.release
        let fileManager = FileManager.default
        let assembled = staging.assembledDirectory
        try fileManager.createDirectory(at: assembled, withIntermediateDirectories: true)

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
                try fileManager.copyItem(at: staging.downloadLocation(for: path), to: assembled.appendingPathComponent(path))
            }
            try published.manifestData.write(to: assembled.appendingPathComponent("manifest.json"))
        } catch {
            Self.logger.error("couldn't copy model files: \(ErrorSummary.of(error), privacy: .public)")
            throw ModelInstallError.installFailed
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

    // Only transport failures mean "no connection"; server answers and local file errors get their own wording.
    static func installError(_ error: Error) -> Error {
        if error is CancellationError { return error }
        logger.error("model download failed: \(ErrorSummary.of(error), privacy: .public)")
        switch error {
        case is URLError: return ModelInstallError.network
        case ModelNetworkError.httpStatus: return ModelInstallError.serverUnavailable
        case let installError as ModelInstallError: return installError
        default: return ModelInstallError.diskWriteFailed
        }
    }
}
