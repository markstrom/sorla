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

    public func removeAll() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        Self.removeRootIfEmpty(root)
    }

    // Staging for the installed version or older can never be used again; newer versions may resume.
    @discardableResult
    public static func removeStale(in modelsDirectory: URL, installedVersion: String?) -> [String] {
        guard let installed = installedVersion.flatMap(SemanticVersion.init) else { return [] }
        let root = modelsDirectory.appendingPathComponent(rootName, isDirectory: true)
        let prefix = "pianissimo-sv-"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
        var removed: [String] = []
        for name in entries where name.hasPrefix(prefix) {
            guard let version = SemanticVersion(String(name.dropFirst(prefix.count))), version <= installed else { continue }
            if (try? FileManager.default.removeItem(at: root.appendingPathComponent(name))) != nil {
                removed.append(name)
            }
        }
        removeRootIfEmpty(root)
        return removed
    }

    private static func removeRootIfEmpty(_ root: URL) {
        if let remaining = try? FileManager.default.contentsOfDirectory(atPath: root.path), remaining.isEmpty {
            try? FileManager.default.removeItem(at: root)
        }
    }
}

public enum DiskSpace {
    // Room for the downloaded packages plus their compiled copies side by side.
    public static func required(forDownloadOf totalSize: Int64) -> Int64 {
        let (doubled, overflow) = totalSize.multipliedReportingOverflow(by: 2)
        return overflow ? .max : doubled
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
