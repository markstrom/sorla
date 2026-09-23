import Foundation
import os

public protocol ModelNetwork: Sendable {
    func data(from url: URL) async throws -> Data
    func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws
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
    private static let logger = Logger(subsystem: "com.prata.app", category: "ModelInstaller")

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
        do {
            data = try await network.data(from: manifestURL)
        } catch {
            throw Self.networkError(error)
        }
        guard let manifest = try? ModelManifest.decode(data),
              let release = manifest.release(id: ModelManifest.pianissimoID)
        else { throw ModelInstallError.invalidManifest }
        return PublishedModel(release: release, manifestData: data)
    }

    // Downloads, verifies, compiles and self-tests into staging; the installed model is never touched here.
    public func stage(_ published: PublishedModel, progress: @escaping @Sendable (ModelInstallProgress) -> Void) async throws -> URL {
        let release = published.release
        try release.validate()
        let staging = ModelStaging(modelsDirectory: modelsDirectory, version: release.version)
        let fileManager = FileManager.default

        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        guard DiskSpace.hasRoom(available: availableDiskSpace(modelsDirectory), forDownloadOf: release.totalSize) else {
            throw ModelInstallError.insufficientDiskSpace(required: DiskSpace.required(forDownloadOf: release.totalSize))
        }
        try? staging.removeOtherVersions()
        try? fileManager.removeItem(at: staging.assembledDirectory)

        try await download(release, into: staging, progress: progress)
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
        let total = max(release.files.reduce(Int64(0)) { $0 + $1.size }, 1)
        let pending = staging.filesNeedingDownload(release.files)
        var completed = total - pending.reduce(Int64(0)) { $0 + $1.size }
        progress(.downloading(fraction: Double(completed) / Double(total)))

        for file in pending {
            try Task.checkCancellation()
            let destination = staging.downloadLocation(for: file.path)
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let base = completed
            do {
                try await network.download(from: ModelStaging.remoteURL(base: filesBaseURL, version: release.version, path: file.path), to: destination) { received in
                    progress(.downloading(fraction: Double(base + min(received, file.size)) / Double(total)))
                }
            } catch {
                throw Self.networkError(error)
            }
            guard FileVerifier.matches(destination, size: file.size, sha256: file.sha256) else {
                try? FileManager.default.removeItem(at: destination)
                Self.logger.error("verification failed: \(file.path, privacy: .public)")
                throw ModelInstallError.verificationFailed(path: file.path)
            }
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
                Self.logger.error("compile failed: \(name, privacy: .public): \(String(describing: error), privacy: .public)")
                throw ModelInstallError.compileFailed
            }
        }
        do {
            for path in [ModelRelease.vocabularyPath, ModelRelease.licensePath] where release.files.contains(where: { $0.path == path }) {
                try fileManager.copyItem(at: staging.downloadLocation(for: path), to: assembled.appendingPathComponent(path))
            }
            try published.manifestData.write(to: assembled.appendingPathComponent("manifest.json"))
        } catch {
            throw ModelInstallError.installFailed
        }
        guard PianissimoModel.hasRequiredFiles(at: assembled) else { throw ModelInstallError.invalidManifest }

        do {
            try await preparer.selfTest(modelDirectory: assembled)
        } catch {
            Self.logger.error("self-test failed: \(String(describing: error), privacy: .public)")
            throw ModelInstallError.selfTestFailed
        }
    }

    private static func networkError(_ error: Error) -> Error {
        if error is CancellationError { return error }
        logger.error("network request failed: \(String(describing: error), privacy: .public)")
        return ModelInstallError.network
    }
}
