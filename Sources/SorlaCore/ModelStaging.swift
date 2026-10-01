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

    // A download in progress sits beside its destination until it is complete.
    public static func partialLocation(for destination: URL) -> URL {
        destination.appendingPathExtension("partial")
    }

    // Downloads left by other versions, which may hold files this version shares with them.
    public var otherVersionsDownloads: [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { $0.lastPathComponent != directory.lastPathComponent }
            .map { $0.appendingPathComponent("download", isDirectory: true) }
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
    // What is still to download, plus: for packages their compiled copies beside them; for compiled models,
    // which are cloned or moved into place, a margin for the file system and what else the Mac writes meanwhile.
    public static func required(forDownloadOf totalSize: Int64, alreadyStaged: Int64 = 0, format: ModelFormat = .packages) -> Int64 {
        let remaining = max(totalSize - min(max(alreadyStaged, 0), totalSize), 0)
        let extra = format == .packages ? totalSize : margin(for: totalSize)
        let (sum, overflow) = remaining.addingReportingOverflow(extra)
        return overflow ? .max : sum
    }

    // A tenth of the model, and at least 200 MB.
    public static func margin(for totalSize: Int64) -> Int64 {
        max(totalSize / 10, 200_000_000)
    }

    public static func hasRoom(available: Int64?, forDownloadOf totalSize: Int64, alreadyStaged: Int64 = 0, format: ModelFormat = .packages) -> Bool {
        guard let available else { return false }
        return available >= required(forDownloadOf: totalSize, alreadyStaged: alreadyStaged, format: format)
    }

    public static func available(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

public enum ModelPlacement: Equatable, Sendable {
    case cloned
    case moved
    case copied
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

    // Leaves the source where it is: for files another model or version still owns.
    @discardableResult
    public func copy(_ source: URL, to destination: URL, canCopy: () -> Bool = { true }) throws -> ModelPlacement {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        do {
            try clone(source, destination)
            return .cloned
        } catch {
            try? fileManager.removeItem(at: destination)
            guard canCopy() else { throw error }
            try fileManager.copyItem(at: source, to: destination)
            return .copied
        }
    }

    // clonefile(2) copies a whole folder in one step on APFS and fails on other file systems.
    @Sendable public static func cloneItem(_ source: URL, _ destination: URL) throws {
        guard clonefile(source.path, destination.path, UInt32(CLONE_NOFOLLOW)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
