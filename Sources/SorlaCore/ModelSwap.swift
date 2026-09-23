import Foundation

// Every step is a rename, or a delete of a copy nobody needs, so recovery can finish any interrupted state.
public struct ModelSwap: Sendable {
    public let modelsDirectory: URL

    public init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    public var installed: URL {
        modelsDirectory.appendingPathComponent(PianissimoModel.directoryName, isDirectory: true)
    }

    public var previous: URL {
        modelsDirectory.appendingPathComponent(PianissimoModel.directoryName + ".old", isDirectory: true)
    }

    public var failed: URL {
        modelsDirectory.appendingPathComponent(PianissimoModel.directoryName + ".failed", isDirectory: true)
    }

    public var trash: URL {
        modelsDirectory.appendingPathComponent(PianissimoModel.directoryName + ".trash", isDirectory: true)
    }

    /// Returns whether it replaced an installed model, which is then kept as `previous` until `commit()`.
    @discardableResult
    public func install(_ staged: URL) throws -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: staged.path) else { throw ModelInstallError.installFailed }
        do {
            try recoverInterruptedSwap()
        } catch {
            throw ModelInstallError.installFailed
        }
        let hadModel = fileManager.fileExists(atPath: installed.path)
        do {
            if hadModel {
                try fileManager.moveItem(at: installed, to: previous)
            }
            try fileManager.moveItem(at: staged, to: installed)
        } catch {
            if hadModel, !fileManager.fileExists(atPath: installed.path) {
                try? fileManager.moveItem(at: previous, to: installed)
            }
            throw ModelInstallError.installFailed
        }
        return hadModel
    }

    // The previous model is renamed away first, so a half-deleted copy is never mistaken for it.
    public func commit() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: trash.path) {
            try fileManager.removeItem(at: trash)
        }
        guard fileManager.fileExists(atPath: previous.path) else { return }
        try fileManager.moveItem(at: previous, to: trash)
        try fileManager.removeItem(at: trash)
    }

    public func rollback() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: installed.path) {
            if fileManager.fileExists(atPath: failed.path) {
                try fileManager.removeItem(at: failed)
            }
            try fileManager.moveItem(at: installed, to: failed)
        }
        if fileManager.fileExists(atPath: previous.path) {
            try fileManager.moveItem(at: previous, to: installed)
        }
        if fileManager.fileExists(atPath: failed.path) {
            try fileManager.removeItem(at: failed)
        }
    }

    // A previous model exists only until the new one has loaded, so whenever it is there it is the one to keep.
    @discardableResult
    public func recoverInterruptedSwap() throws -> String? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: trash.path) {
            try fileManager.removeItem(at: trash)
        }
        guard fileManager.fileExists(atPath: previous.path) else {
            if fileManager.fileExists(atPath: failed.path) {
                try fileManager.removeItem(at: failed)
            }
            return nil
        }
        let discarded = PianissimoModel.installedVersion(at: installed)
        try rollback()
        return discarded
    }
}
