import Foundation

// Kept beside the model so a bad release isn't downloaded and loaded again by every automatic check.
public struct FailedModelUpdate: Sendable {
    public static let fileName = ".failed-version"

    public let modelsDirectory: URL

    public init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    private var file: URL { modelsDirectory.appendingPathComponent(Self.fileName) }

    public var version: String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let version = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    public func record(_ version: String) throws {
        try Data(version.utf8).write(to: file, options: .atomic)
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
