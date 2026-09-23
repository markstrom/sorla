import Foundation

public struct ModelManifest: Decodable, Sendable {
    public static let pianissimoID = "pianissimo-sv"

    public let schema: Int
    public let models: [ModelRelease]

    public static func decode(_ data: Data) throws -> ModelManifest {
        try JSONDecoder().decode(ModelManifest.self, from: data)
    }

    public func release(id: String) -> ModelRelease? {
        models.first { $0.id == id }
    }
}

public struct ModelLoader: Codable, Equatable, Sendable {
    public let library: String
    public let version: String

    public init(library: String, version: String) {
        self.library = library
        self.version = version
    }
}

public struct ModelFile: Codable, Equatable, Sendable {
    public let path: String
    public let size: Int64
    public let sha256: String

    public init(path: String, size: Int64, sha256: String) {
        self.path = path
        self.size = size
        self.sha256 = sha256
    }
}

public struct ModelRelease: Decodable, Equatable, Sendable {
    public static let supportedLoader = ModelLoader(library: "FluidAudio", version: "v3")
    public static let vocabularyPath = "parakeet_vocab.json"
    public static let licensePath = "LICENSE-and-attribution.txt"
    // Far above the ~700 MB model; sizes come from the network and must stay clear of Int64 overflow.
    public static let maximumTotalSize: Int64 = 10_000_000_000

    public let id: String
    public let name: String
    public let version: String
    public let loader: ModelLoader?
    public let totalSize: Int64
    public let files: [ModelFile]

    public init(id: String, name: String, version: String, loader: ModelLoader?, totalSize: Int64, files: [ModelFile]) {
        self.id = id
        self.name = name
        self.version = version
        self.loader = loader
        self.totalSize = totalSize
        self.files = files
    }

    public var semanticVersion: SemanticVersion? { SemanticVersion(version) }

    public var isCompatible: Bool { loader == Self.supportedLoader }

    public var packageNames: [String] {
        let names = files.compactMap { file -> String? in
            guard let first = file.path.split(separator: "/").first, first.hasSuffix(".mlpackage") else { return nil }
            return String(first.dropLast(".mlpackage".count))
        }
        return Array(Set(names)).sorted()
    }

    public func validate() throws {
        guard semanticVersion != nil else { throw ModelInstallError.invalidManifest }
        guard files.contains(where: { $0.path == Self.vocabularyPath }) else { throw ModelInstallError.invalidManifest }
        for file in files {
            guard Self.isSafeRelativePath(file.path), Self.isSHA256Hex(file.sha256), file.size >= 0 else {
                throw ModelInstallError.invalidManifest
            }
        }
        guard (0...Self.maximumTotalSize).contains(totalSize), Self.checkedSum(files.map(\.size)) == totalSize else {
            throw ModelInstallError.invalidManifest
        }
    }

    public static func checkedSum(_ sizes: [Int64]) -> Int64? {
        var sum: Int64 = 0
        for size in sizes {
            let (next, overflow) = sum.addingReportingOverflow(size)
            if overflow { return nil }
            sum = next
        }
        return sum
    }

    // Paths come from the network, so they must never resolve outside the staging directory.
    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func isSHA256Hex(_ hash: String) -> Bool {
        hash.count == 64 && hash.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }
}
