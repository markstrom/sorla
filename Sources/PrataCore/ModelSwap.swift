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

    public func install(_ staged: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: staged.path) else { throw ModelInstallError.installFailed }
        if fileManager.fileExists(atPath: previous.path) {
            try? fileManager.removeItem(at: previous)
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

    public func rollback() throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: installed)
        guard fileManager.fileExists(atPath: previous.path) else { return }
        do {
            try fileManager.moveItem(at: previous, to: installed)
        } catch {
            throw ModelInstallError.installFailed
        }
    }

    // A quit between the two renames leaves only the previous model; a quit before commit leaves both.
    public func recoverInterruptedSwap() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: previous.path) else { return }
        if fileManager.fileExists(atPath: installed.path) {
            commit()
        } else {
            try? fileManager.moveItem(at: previous, to: installed)
        }
    }
}
