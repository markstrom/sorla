import Foundation
import Security

public enum ProcessRunner {
    public struct Result: Equatable, Sendable {
        public let status: Int32
        public let output: String
    }

    // An argument array and no shell, so no path can become a command; a hung tool is stopped after the timeout.
    public static func run(_ executable: URL, arguments: [String], timeout: TimeInterval) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: Result(status: finished.terminationStatus, output: String(decoding: data, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}

public enum AppInstallSystemError: Error, Equatable, Sendable {
    case status(Int32)
}

public struct URLSessionAppUpdateDownloader: AppUpdateDownloading {
    private let network: ModelNetwork

    public init(network: ModelNetwork = URLSessionModelNetwork()) {
        self.network = network
    }

    public func download(_ url: URL, to destination: URL, maximumBytes: Int64) async throws {
        try await network.download(from: url, to: destination, maxBytes: maximumBytes, progress: { _ in })
    }
}

public struct HdiutilDiskImageMounter: DiskImageMounting {
    public init() {}

    public func attach(_ image: URL, at mountPoint: URL) async throws {
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let result = try await ProcessRunner.run(DiskImageCommand.hdiutil, arguments: DiskImageCommand.attachArguments(image: image, mountPoint: mountPoint), timeout: 120)
        guard result.status == 0 else { throw AppInstallSystemError.status(result.status) }
    }

    public func detach(_ mountPoint: URL) async {
        guard Self.isMounted(mountPoint) else { return }
        for force in [false, true] {
            let result = try? await ProcessRunner.run(DiskImageCommand.hdiutil, arguments: DiskImageCommand.detachArguments(mountPoint: mountPoint, force: force), timeout: 60)
            if result?.status == 0 { return }
        }
    }

    // A mounted volume sits on another device than the folder holding its mount point.
    static func isMounted(_ mountPoint: URL) -> Bool {
        let device = { (url: URL) in (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemNumber] as? NSNumber }
        guard let inside = device(mountPoint), let outside = device(mountPoint.deletingLastPathComponent()) else { return false }
        return inside != outside
    }
}

public struct SecurityAppSignatureChecker: AppSignatureChecking {
    static let spctl = URL(fileURLWithPath: "/usr/sbin/spctl")

    public init() {}

    public func checkSignature(of app: URL, requirement text: String) throws {
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(app as CFURL, [], &code)
        guard status == errSecSuccess, let code else { throw AppInstallSystemError.status(status) }
        var requirement: SecRequirement?
        status = SecRequirementCreateWithString(text as CFString, [], &requirement)
        guard status == errSecSuccess, let requirement else { throw AppInstallSystemError.status(status) }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        status = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else { throw AppInstallSystemError.status(status) }
    }

    public func checkNotarized(_ app: URL) async throws {
        let result = try await ProcessRunner.run(Self.spctl, arguments: GatekeeperAssessment.arguments + [app.path], timeout: 120)
        guard GatekeeperAssessment.isNotarized(status: result.status, output: result.output) else {
            throw AppInstallSystemError.status(result.status)
        }
    }
}

public struct SystemAppFileOperations: AppFileOperations {
    public static let directoryPrefix = "Sorla-update-"
    private let root: URL

    public init(root: URL = FileManager.default.temporaryDirectory) {
        self.root = root
    }

    // Inside the user's own temporary folder, and readable by no one else.
    public func makePrivateDirectory() throws -> URL {
        let directory = root.appendingPathComponent(Self.directoryPrefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }

    public func leftoverDirectories() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { $0.hasPrefix(Self.directoryPrefix) }.sorted().map { root.appendingPathComponent($0, isDirectory: true) }
    }

    public func size(of url: URL) -> Int64? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value
    }

    public func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    // attributesOfItem doesn't follow a symlink, so a link reads as a link.
    public func isDirectory(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeDirectory
    }

    public func copy(_ source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func move(_ source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func replace(_ item: URL, with replacement: URL, backupName: String?) throws {
        _ = try FileManager.default.replaceItemAt(
            item,
            withItemAt: replacement,
            backupItemName: backupName,
            options: backupName == nil ? [] : .withoutDeletingBackupItem
        )
    }

    // Read from disk each time; Bundle caches what it read first.
    public func shortVersion(of app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }
}

@MainActor
public final class SystemAppRelauncher: AppRelaunching {
    private var helper: Process?

    public init() {}

    public func start(waitingFor pid: Int32, thenOpen bundle: URL, expectedVersion: String?) throws {
        let helper = Process()
        helper.executableURL = AppRelaunch.shell
        helper.arguments = AppRelaunch.arguments(waitingFor: pid, thenOpen: bundle, expectedVersion: expectedVersion)
        try helper.run()
        self.helper = helper
    }

    // Quitting was called off, so the helper must not open anything once this Sorla quits later.
    public func cancel() {
        if helper?.isRunning == true { helper?.terminate() }
        helper = nil
    }
}
