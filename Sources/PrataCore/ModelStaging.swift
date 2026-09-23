import Foundation

public struct ModelStaging: Sendable {
    public static let rootName = ".staging"

    public let modelsDirectory: URL
    public let version: String

    public init(modelsDirectory: URL, version: String) {
        self.modelsDirectory = modelsDirectory
        self.version = version
    }

    public var root: URL { modelsDirectory.appendingPathComponent(Self.rootName, isDirectory: true) }
    public var directory: URL { root.appendingPathComponent("pianissimo-sv-\(version)", isDirectory: true) }
    public var downloadsDirectory: URL { directory.appendingPathComponent("download", isDirectory: true) }
    public var assembledDirectory: URL { directory.appendingPathComponent("model", isDirectory: true) }

    public func downloadLocation(for path: String) -> URL {
        downloadsDirectory.appendingPathComponent(path)
    }

    public static func remoteURL(base: URL, version: String, path: String) -> URL {
        base.appendingPathComponent(version).appendingPathComponent(path)
    }

    public func filesNeedingDownload(_ files: [ModelFile]) -> [ModelFile] {
        files.filter { !FileVerifier.matches(downloadLocation(for: $0.path), size: $0.size, sha256: $0.sha256) }
    }

    public func removeOtherVersions() throws {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.lastPathComponent != directory.lastPathComponent {
            try fileManager.removeItem(at: entry)
        }
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        if let remaining = try? FileManager.default.contentsOfDirectory(atPath: root.path), remaining.isEmpty {
            try? FileManager.default.removeItem(at: root)
        }
    }
}

public enum DiskSpace {
    // Room for the downloaded packages plus their compiled copies side by side.
    public static func required(forDownloadOf totalSize: Int64) -> Int64 {
        totalSize * 2
    }

    public static func hasRoom(available: Int64?, forDownloadOf totalSize: Int64) -> Bool {
        guard let available else { return false }
        return available >= required(forDownloadOf: totalSize)
    }

    public static func available(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
