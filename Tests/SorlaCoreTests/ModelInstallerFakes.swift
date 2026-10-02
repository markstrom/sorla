import Foundation
@testable import SorlaCore

actor FakeModelNetwork: ModelNetwork {
    private(set) var requests: [URL] = []
    private(set) var resumed: [URL] = []
    private(set) var accesses: [URL: ModelNetworkAccess] = [:]
    private(set) var downloadLimits: [URL: Int64] = [:]
    // Stands in for a hotspot or Low Data Mode: URLSession refuses `.inexpensiveOnly` requests with this reason.
    private var costlyNetwork: URLError.NetworkUnavailableReason?
    private var costlyAfterRequests = 0
    private var responses: [URL: Data] = [:]
    private var failing: Set<URL> = []
    private var errors: [URL: Error] = [:]
    private var holdsDownloads = false
    private var heldDownloads: [CheckedContinuation<Void, Never>] = []
    private var heldDownloadWaiters: [CheckedContinuation<Void, Never>] = []

    func serve(_ data: Data, at url: URL) {
        responses[url] = data
    }

    func fail(_ url: URL) {
        failing.insert(url)
    }

    func unfail(_ url: URL) {
        failing.remove(url)
    }

    func fail(_ url: URL, with error: Error) {
        errors[url] = error
    }

    // `afterRequests` lets the first requests through, as when the Mac joins a hotspot mid-download.
    func useCostlyNetwork(_ reason: URLError.NetworkUnavailableReason? = .expensive, afterRequests: Int = 0) {
        costlyNetwork = reason
        costlyAfterRequests = requests.count + afterRequests
    }

    private func refuseIfCostly(_ url: URL, access: ModelNetworkAccess) throws {
        guard access == .inexpensiveOnly, let costlyNetwork, requests.count > costlyAfterRequests else { return }
        throw URLError(.notConnectedToInternet, userInfo: [NSURLErrorNetworkUnavailableReasonKey: costlyNetwork.rawValue])
    }

    func holdDownloads() {
        holdsDownloads = true
    }

    func releaseDownloads() {
        holdsDownloads = false
        heldDownloads.forEach { $0.resume() }
        heldDownloads = []
    }

    // Returns once a download has been requested and is being held.
    func waitForHeldDownload() async {
        guard heldDownloads.isEmpty else { return }
        await withCheckedContinuation { heldDownloadWaiters.append($0) }
    }

    func data(from url: URL, access: ModelNetworkAccess) async throws -> Data {
        requests.append(url)
        accesses[url] = access
        try refuseIfCostly(url, access: access)
        if let error = errors[url] { throw error }
        guard !failing.contains(url), let data = responses[url] else { throw URLError(.notConnectedToInternet) }
        return data
    }

    func download(from url: URL, to destination: URL, maxBytes: Int64, access: ModelNetworkAccess, progress: @escaping @Sendable (Int64) -> Void) async throws {
        requests.append(url)
        accesses[url] = access
        downloadLimits[url] = maxBytes
        try refuseIfCostly(url, access: access)
        if holdsDownloads {
            await withCheckedContinuation { held in
                heldDownloads.append(held)
                heldDownloadWaiters.forEach { $0.resume() }
                heldDownloadWaiters = []
            }
        }
        if let error = errors[url] { throw error }
        guard !failing.contains(url), let data = responses[url] else { throw URLError(.notConnectedToInternet) }
        guard Int64(data.count) <= maxBytes else { throw ModelNetworkError.tooLarge }
        // Like the real network, a partial file left beside the destination is continued, whatever it holds.
        let partial = ModelStaging.partialLocation(for: destination)
        var body = data
        if let earlier = try? Data(contentsOf: partial) {
            resumed.append(url)
            body = earlier.count < data.count ? earlier + data.suffix(from: earlier.count) : data
            try FileManager.default.removeItem(at: partial)
        }
        try body.write(to: destination)
        progress(Int64(body.count))
    }
}

actor FakeModelPreparer: ModelPreparer {
    private(set) var compiled: [String] = []
    private(set) var selfTested: [URL] = []
    private var selfTestFails = false
    private var compileFails = false

    private var precompiledSelfTestFails = false

    func failSelfTest() { selfTestFails = true }
    // Only a model whose weights arrived precompiled, as when the compiled release won't load on some macOS.
    func failSelfTestOfPrecompiledModels() { precompiledSelfTestFails = true }
    func failCompile() { compileFails = true }

    func compile(package: URL, into destination: URL) async throws {
        if compileFails { throw CocoaError(.fileReadCorruptFile) }
        compiled.append(package.lastPathComponent)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data(package.lastPathComponent.utf8).write(to: destination.appendingPathComponent("compiled"))
    }

    func selfTest(modelDirectory: URL) async throws {
        selfTested.append(modelDirectory)
        if selfTestFails { throw CocoaError(.fileReadCorruptFile) }
        let precompiled = FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent("Encoder.mlmodelc/weights/weight.bin").path)
        if precompiledSelfTestFails, precompiled { throw CocoaError(.fileReadCorruptFile) }
    }
}

struct PublishedModelFixture {
    // Package releases are served where the packages pin points; compiled ones from a folder of their own.
    static let manifestURL = URL(string: "https://models.test/pianissimo/resolve/0a1b2c/manifest.json")!
    static let compiledManifestURL = URL(string: "https://models.test/pianissimo/resolve/3d4e5f/compiled/manifest.json")!
    static let modelNames = ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"]

    let version: String
    let format: ModelFormat
    let contents: [String: String]
    private let loaderVersion: String

    init(version: String = "1.1.0", loaderVersion: String = "v3", format: ModelFormat = .packages) {
        self.version = version
        self.loaderVersion = loaderVersion
        self.format = format
        var contents = [
            "parakeet_vocab.json": "{\"0\":\"a\"}",
            "LICENSE-and-attribution.txt": "license \(version)",
        ]
        switch format {
        case .packages:
            contents["Preprocessor.mlpackage/Manifest.json"] = "pre"
            contents["Encoder.mlpackage/Manifest.json"] = "enc"
            contents["Encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin"] = String(repeating: "w", count: 4096)
            contents["Decoder.mlpackage/Manifest.json"] = "dec"
            contents["JointDecisionv3.mlpackage/Manifest.json"] = "joint"
            contents["README.md"] = "readme"
        case .compiled:
            for name in Self.modelNames {
                contents["\(name).mlmodelc/coremldata.bin"] = "compiled \(name)"
                contents["\(name).mlmodelc/weights/weight.bin"] = String(repeating: "w", count: name == "Encoder" ? 4096 : 64)
            }
        }
        self.contents = contents
    }

    var manifestURL: URL { format == .packages ? Self.manifestURL : Self.compiledManifestURL }

    var pin: ModelPin {
        ModelPin(version: version, manifestURL: manifestURL, manifestSHA256: ModelStagingTests.sha256(of: manifestData))
    }

    var files: [ModelFile] {
        contents.keys.sorted().map { path in
            ModelFile(path: path, size: Int64(contents[path]!.utf8.count), sha256: ModelStagingTests.sha256(of: Data(contents[path]!.utf8)))
        }
    }

    var release: ModelRelease {
        ModelRelease(
            id: "pianissimo-sv",
            name: "Pianissimo (Swedish)",
            version: version,
            loader: ModelLoader(library: "FluidAudio", version: loaderVersion),
            totalSize: files.reduce(0) { $0 + $1.size },
            files: files,
            format: format == .compiled ? "mlmodelc" : nil,
            minimumOS: format == .compiled ? ModelMinimumOS(macOS: "26.0") : nil
        )
    }

    var manifestData: Data {
        let fileEntries = files.map { ["path": $0.path, "size": $0.size, "sha256": $0.sha256] as [String: Any] }
        var model: [String: Any] = [
            "id": "pianissimo-sv",
            "name": "Pianissimo (Swedish)",
            "version": version,
            "loader": ["library": "FluidAudio", "version": loaderVersion],
            "totalSize": files.reduce(0) { $0 + $1.size },
            "files": fileEntries,
        ]
        if format == .compiled {
            model["format"] = "mlmodelc"
            model["minimumOS"] = ["iOS": "26.0", "macOS": "26.0"]
        }
        return try! JSONSerialization.data(withJSONObject: ["schema": 1, "models": [model]], options: [.sortedKeys])
    }

    func url(for path: String) -> URL {
        manifestURL.deletingLastPathComponent().appendingPathComponent(path)
    }

    func publish(on network: FakeModelNetwork) async {
        await network.serve(manifestData, at: manifestURL)
        for (path, body) in contents {
            await network.serve(Data(body.utf8), at: url(for: path))
        }
    }
}

extension SemanticVersion {
    static let sonoma = SemanticVersion(major: 14, minor: 0, patch: 0)
    static let sequoia = SemanticVersion(major: 15, minor: 7, patch: 0)
    static let tahoe = SemanticVersion(major: 26, minor: 0, patch: 0)
}

// Stands in for the path monitor; keeps the callback after stop, like a path update that arrives late.
@MainActor
final class FakeNetworkWatcher: InexpensiveNetworkWatching {
    private(set) var isWatching = false
    // Every watch's callback, oldest first, so a test can fire one from an earlier watch late.
    private var callbacks: [@MainActor () -> Void] = []

    nonisolated init() {}

    func start(onAvailable: @escaping @MainActor () -> Void) {
        isWatching = true
        callbacks.append(onAvailable)
    }

    func stop() {
        isWatching = false
    }

    func becomeAvailable() {
        callbacks.last?()
    }

    func becomeAvailableForTheFirstWatch() {
        callbacks.first?()
    }
}
