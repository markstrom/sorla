import Foundation
import os
@testable import SorlaCore

// A Sorla.app as the fakes see it: its version, and whether it passes each check.
struct FakeApp: Equatable, Sendable {
    var version: String
    var isSignedBySorla = true
    var isNotarized = true
}

// A disk in memory: paths hold an app, a disk image with an app inside, or a folder; nothing touches the real disk.
final class FakeAppDisk: AppFileOperations, Sendable {
    enum Item: Equatable, Sendable {
        case folder
        case app(FakeApp)
        case image(size: Int64, app: FakeApp?)
    }

    struct State: Sendable {
        var items: [String: Item] = [:]
        var log: [String] = []
        var failing: Set<String> = []
        var directories = 0
        // Makes the next copy come out as another version, as if something changed it on the way.
        var copiesBecome: FakeApp?
        // Makes replace move the original away and then fail, as a swap cut short would.
        var replaceFailsHalfway = false
    }

    let state = OSAllocatedUnfairLock(initialState: State())

    func item(_ path: String) -> Item? { state.withLock { $0.items[path] } }
    func set(_ path: String, _ item: Item?) { state.withLock { $0.items[path] = item } }
    func fail(_ operation: String) { state.withLock { _ = $0.failing.insert(operation) } }
    var log: [String] { state.withLock { $0.log } }
    var paths: [String] { state.withLock { $0.items.keys.sorted() } }

    private func record(_ entry: String, operation: String) throws {
        let fails = state.withLock { state -> Bool in
            state.log.append(entry)
            return state.failing.contains(operation)
        }
        if fails { throw CocoaError(.fileWriteUnknown) }
    }

    private static func isInside(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    func makePrivateDirectory() throws -> URL {
        try record("make directory", operation: "makeDirectory")
        return state.withLock { state in
            state.directories += 1
            let path = "/private/tmp/Sorla-update-\(state.directories)"
            state.items[path] = .folder
            return URL(fileURLWithPath: path)
        }
    }

    func leftoverDirectories() -> [URL] {
        paths.filter { $0.hasPrefix("/private/tmp/Sorla-update-") && !$0.dropFirst("/private/tmp/".count).contains("/") }
            .map { URL(fileURLWithPath: $0) }
    }

    func size(of url: URL) -> Int64? {
        if case .image(let size, _) = item(url.path) { return size }
        return nil
    }

    func exists(_ url: URL) -> Bool {
        state.withLock { state in state.items.keys.contains { Self.isInside($0, url.path) } }
    }

    func copy(_ source: URL, to destination: URL) throws {
        try record("copy \(source.lastPathComponent) to \(destination.path)", operation: "copy")
        state.withLock { state in
            for (path, item) in state.items where Self.isInside(path, source.path) {
                var copied = item
                if case .app = item, let replacement = state.copiesBecome { copied = .app(replacement) }
                state.items[destination.path + path.dropFirst(source.path.count)] = copied
            }
        }
    }

    func move(_ source: URL, to destination: URL) throws {
        try record("move \(source.lastPathComponent) to \(destination.lastPathComponent)", operation: "move")
        state.withLock { Self.move(source.path, to: destination.path, in: &$0.items) }
    }

    func remove(_ url: URL) throws {
        try record("remove \(url.path)", operation: "remove")
        state.withLock { state in state.items = state.items.filter { !Self.isInside($0.key, url.path) } }
    }

    func replace(_ item: URL, with replacement: URL, backupName: String?) throws {
        try record("replace \(item.lastPathComponent) with \(replacement.lastPathComponent)", operation: "replace")
        let backup = item.deletingLastPathComponent().appendingPathComponent(backupName ?? ".replaced").path
        let halfway = state.withLock { state -> Bool in
            Self.move(item.path, to: backup, in: &state.items)
            return state.replaceFailsHalfway
        }
        if halfway { throw CocoaError(.fileWriteUnknown) }
        state.withLock { state in
            Self.move(replacement.path, to: item.path, in: &state.items)
            if backupName == nil { state.items = state.items.filter { !Self.isInside($0.key, backup) } }
        }
    }

    func shortVersion(of app: URL) -> String? {
        if case .app(let app) = item(app.path) { return app.version }
        return nil
    }

    private static func move(_ source: String, to destination: String, in items: inout [String: Item]) {
        for (path, item) in items where isInside(path, source) {
            items[path] = nil
            items[destination + path.dropFirst(source.count)] = item
        }
    }
}

// Writes the disk image a test chose, or fails the way a network can.
final class FakeAppDownloader: AppUpdateDownloading, Sendable {
    struct State: Sendable {
        var image: FakeAppDisk.Item = .image(size: 11_000_000, app: FakeApp(version: "1.1.0"))
        var error: Error?
        var requests: [(url: URL, maximumBytes: Int64)] = []
    }

    let disk: FakeAppDisk
    let state = OSAllocatedUnfairLock(initialState: State())

    init(disk: FakeAppDisk) {
        self.disk = disk
    }

    var requests: [(url: URL, maximumBytes: Int64)] { state.withLock { $0.requests } }

    func serve(_ image: FakeAppDisk.Item) { state.withLock { $0.image = image } }
    func fail(with error: Error) { state.withLock { $0.error = error } }

    func download(_ url: URL, to destination: URL, maximumBytes: Int64) async throws {
        let (image, error) = state.withLock { state in
            state.requests.append((url, maximumBytes))
            return (state.image, state.error)
        }
        if let error { throw error }
        disk.set(destination.path, image)
    }
}

// Mounting puts the image's app at the mount point; detaching takes it away again.
final class FakeMounter: DiskImageMounting, Sendable {
    let disk: FakeAppDisk
    let state = OSAllocatedUnfairLock(initialState: (fails: false, attached: [String](), detached: [String]()))

    init(disk: FakeAppDisk) {
        self.disk = disk
    }

    var attached: [String] { state.withLock { $0.attached } }
    var detached: [String] { state.withLock { $0.detached } }
    func failAttach() { state.withLock { $0.fails = true } }

    func attach(_ image: URL, at mountPoint: URL) async throws {
        let fails = state.withLock { state -> Bool in
            state.attached.append(mountPoint.path)
            return state.fails
        }
        guard !fails, case .image(_, let app) = disk.item(image.path) else { throw CocoaError(.fileReadCorruptFile) }
        disk.set(mountPoint.path, .folder)
        if let app { disk.set(mountPoint.appendingPathComponent("Sorla.app").path, .app(app)) }
    }

    func detach(_ mountPoint: URL) async {
        state.withLock { $0.detached.append(mountPoint.path) }
        try? disk.remove(mountPoint)
    }
}

struct FakeSignatures: AppSignatureChecking {
    let disk: FakeAppDisk

    func checkSignature(of app: URL, requirement: String) throws {
        guard requirement == AppInstallPolicy.codeRequirement, case .app(let found) = disk.item(app.path), found.isSignedBySorla else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func checkNotarized(_ app: URL) async throws {
        guard case .app(let found) = disk.item(app.path), found.isNotarized else { throw CocoaError(.fileReadCorruptFile) }
    }
}

@MainActor
final class FakeRelauncher: AppRelaunching {
    var starts: [(pid: Int32, bundle: URL, version: String?)] = []
    var cancels = 0
    var error: Error?

    func start(waitingFor pid: Int32, thenOpen bundle: URL, expectedVersion: String?) throws {
        if let error { throw error }
        starts.append((pid, bundle, expectedVersion))
    }

    func cancel() {
        cancels += 1
    }
}

enum AppInstallFixtures {
    static let bundle = URL(fileURLWithPath: "/Users/test/Applications/Sorla.app")
    static let backup = URL(fileURLWithPath: "/Users/test/Applications/Sorla 1.0.0.app")
    static let staged = URL(fileURLWithPath: "/Users/test/Applications/.Sorla-update.app")
    static let pin = PinnedRelease(
        tag: "v1.1.0",
        version: "1.1.0",
        assetURL: URL(string: "https://github.com/markstrom/sorla/releases/download/v1.1.0/Sorla-1.1.0.dmg")!,
        assetSize: 11_000_000
    )

    static func makeDisk() -> FakeAppDisk {
        let disk = FakeAppDisk()
        disk.set(bundle.path, .app(FakeApp(version: "1.0.0")))
        return disk
    }

    static func makeInstaller(disk: FakeAppDisk, downloader: FakeAppDownloader, mounter: FakeMounter, running: String? = "1.0.0") -> AppInstaller {
        AppInstaller(
            bundleURL: bundle,
            runningVersion: running,
            downloader: downloader,
            mounter: mounter,
            signatures: FakeSignatures(disk: disk),
            files: disk
        )
    }
}
