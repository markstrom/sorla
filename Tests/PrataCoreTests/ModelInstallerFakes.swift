import Foundation
@testable import PrataCore

actor FakeModelNetwork: ModelNetwork {
    private(set) var requests: [URL] = []
    private var responses: [URL: Data] = [:]
    private var failing: Set<URL> = []

    func serve(_ data: Data, at url: URL) {
        responses[url] = data
    }

    func fail(_ url: URL) {
        failing.insert(url)
    }

    func data(from url: URL) async throws -> Data {
        requests.append(url)
        guard !failing.contains(url), let data = responses[url] else { throw URLError(.notConnectedToInternet) }
        return data
    }

    func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        requests.append(url)
        guard !failing.contains(url), let data = responses[url] else { throw URLError(.notConnectedToInternet) }
        try data.write(to: destination)
        progress(Int64(data.count))
    }
}

actor FakeModelPreparer: ModelPreparer {
    private(set) var compiled: [String] = []
    private(set) var selfTested: [URL] = []
    private var selfTestFails = false
    private var compileFails = false

    func failSelfTest() { selfTestFails = true }
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
    }
}

struct PublishedModelFixture {
    static let manifestURL = URL(string: "https://models.test/pianissimo/resolve/main/manifest.json")!
    static let filesBaseURL = URL(string: "https://models.test/pianissimo/resolve")!

    let version: String
    let contents: [String: String]

    init(version: String = "1.1.0", loaderVersion: String = "v3") {
        self.version = version
        self.loaderVersion = loaderVersion
        contents = [
            "Preprocessor.mlpackage/Manifest.json": "pre",
            "Encoder.mlpackage/Manifest.json": "enc",
            "Encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin": String(repeating: "w", count: 4096),
            "Decoder.mlpackage/Manifest.json": "dec",
            "JointDecisionv3.mlpackage/Manifest.json": "joint",
            "parakeet_vocab.json": "{\"0\":\"a\"}",
            "LICENSE-and-attribution.txt": "license \(version)",
            "README.md": "readme",
        ]
    }

    private let loaderVersion: String

    var files: [ModelFile] {
        contents.keys.sorted().map { path in
            ModelFile(path: path, size: Int64(contents[path]!.utf8.count), sha256: ModelStagingTests.sha256(contents[path]!))
        }
    }

    var release: ModelRelease {
        ModelRelease(
            id: "pianissimo-sv",
            name: "Pianissimo (Swedish)",
            version: version,
            loader: ModelLoader(library: "FluidAudio", version: loaderVersion),
            totalSize: files.reduce(0) { $0 + $1.size },
            files: files
        )
    }

    var manifestData: Data {
        let fileEntries = files.map { ["path": $0.path, "size": $0.size, "sha256": $0.sha256] as [String: Any] }
        let model: [String: Any] = [
            "id": "pianissimo-sv",
            "name": "Pianissimo (Swedish)",
            "version": version,
            "loader": ["library": "FluidAudio", "version": loaderVersion],
            "totalSize": files.reduce(0) { $0 + $1.size },
            "files": fileEntries,
        ]
        return try! JSONSerialization.data(withJSONObject: ["schema": 1, "models": [model]], options: [.sortedKeys])
    }

    func url(for path: String) -> URL {
        ModelStaging.remoteURL(base: Self.filesBaseURL, version: version, path: path)
    }

    func publish(on network: FakeModelNetwork) async {
        await network.serve(manifestData, at: Self.manifestURL)
        for (path, body) in contents {
            await network.serve(Data(body.utf8), at: url(for: path))
        }
    }
}
