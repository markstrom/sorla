import Foundation

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

    public func install(_ staged: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: staged.path) else { throw ModelInstallError.installFailed }
        if fileManager.fileExists(atPath: previous.path) {
            try? fileManager.removeItem(at: previous)
        }
        if fileManager.fileExists(atPath: failed.path) {
            try? fileManager.removeItem(at: failed)
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
    }

    public func commit() {
        try? FileManager.default.removeItem(at: previous)
    }

    // Only renames until the previous model is back, so a crash midway leaves states recovery can finish.
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

    // A previous model that is alone or beside a failed one is the last known-good copy, so it wins.
    public func recoverInterruptedSwap() throws {
        let fileManager = FileManager.default
        let hasFailed = fileManager.fileExists(atPath: failed.path)
        if fileManager.fileExists(atPath: previous.path) {
            if hasFailed || !fileManager.fileExists(atPath: installed.path) {
                if fileManager.fileExists(atPath: installed.path) {
                    try fileManager.removeItem(at: installed)
                }
                try fileManager.moveItem(at: previous, to: installed)
            } else {
                commit()
            }
        }
        if hasFailed {
            try fileManager.removeItem(at: failed)
        }
    }
}
