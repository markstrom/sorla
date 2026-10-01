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

    @discardableResult
    public static func removeEverything(in modelsDirectory: URL) -> [String] {
        let root = modelsDirectory.appendingPathComponent(rootName, isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let removed = entries.filter { (try? FileManager.default.removeItem(at: root.appendingPathComponent($0))) != nil }
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
    // Packages need room for the downloads plus their compiled copies side by side;
    // compiled models are cloned or moved into place, so one copy is enough.
    public static func required(forDownloadOf totalSize: Int64, format: ModelFormat = .packages) -> Int64 {
        switch format {
        case .packages:
            let (doubled, overflow) = totalSize.multipliedReportingOverflow(by: 2)
            return overflow ? .max : doubled
        case .compiled:
            return totalSize
        }
    }

    public static func hasRoom(available: Int64?, forDownloadOf totalSize: Int64, format: ModelFormat = .packages) -> Bool {
        guard let available else { return false }
        return available >= required(forDownloadOf: totalSize, format: format)
    }

    public static func available(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

public enum ModelPlacement: Equatable, Sendable {
    case cloned
    case moved
}

// An APFS clone shares the verified download's blocks, so a failed self-test can retry without downloading again.
// Where cloning isn't possible the download is moved instead, which still needs no second copy.
public struct ModelFilePlacer: Sendable {
    private let clone: @Sendable (URL, URL) throws -> Void

    public init(clone: @escaping @Sendable (URL, URL) throws -> Void = ModelFilePlacer.cloneItem) {
        self.clone = clone
    }

    @discardableResult
    public func place(_ source: URL, at destination: URL) throws -> ModelPlacement {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        do {
            try clone(source, destination)
            return .cloned
        } catch {
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: source, to: destination)
            return .moved
        }
    }

    // clonefile(2) copies a whole folder in one step on APFS and fails on other file systems.
    @Sendable public static func cloneItem(_ source: URL, _ destination: URL) throws {
        guard clonefile(source.path, destination.path, UInt32(CLONE_NOFOLLOW)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
