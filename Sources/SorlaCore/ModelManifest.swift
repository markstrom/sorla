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

// How a release ships its models: Core ML packages Sorla compiles on the Mac, or models compiled ahead for one minimum macOS.
public enum ModelFormat: String, Equatable, Sendable {
    case packages = "mlpackage"
    case compiled = "mlmodelc"
}

public struct ModelMinimumOS: Codable, Equatable, Sendable {
    public let macOS: String?

    public init(macOS: String?) {
        self.macOS = macOS
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
    // Absent in the package releases, which predate it.
    public let format: String?
    public let minimumOS: ModelMinimumOS?

    public init(
        id: String, name: String, version: String, loader: ModelLoader?, totalSize: Int64, files: [ModelFile],
        format: String? = nil, minimumOS: ModelMinimumOS? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.loader = loader
        self.totalSize = totalSize
        self.files = files
        self.format = format
        self.minimumOS = minimumOS
    }

    public var semanticVersion: SemanticVersion? { SemanticVersion(version) }

    public var isCompatible: Bool { loader == Self.supportedLoader }

    public var modelFormat: ModelFormat? {
        guard let format else { return .packages }
        return ModelFormat(rawValue: format)
    }

    public var packageNames: [String] { topLevelNames(withExtension: "mlpackage") }

    public var compiledModelNames: [String] { topLevelNames(withExtension: "mlmodelc") }

    private func topLevelNames(withExtension pathExtension: String) -> [String] {
        let suffix = "." + pathExtension
        let names = files.compactMap { file -> String? in
            guard let first = file.path.split(separator: "/").first, first.hasSuffix(suffix) else { return nil }
            return String(first.dropLast(suffix.count))
        }
        return Array(Set(names)).sorted()
    }

    // Everything here comes from the network; `system` is the running macOS, passed in so tests can choose it.
    public func validate(runningOn system: SemanticVersion = .runningSystem) throws {
        guard semanticVersion != nil else { throw ModelInstallError.invalidManifest }
        guard files.contains(where: { $0.path == Self.vocabularyPath }) else { throw ModelInstallError.invalidManifest }
        for file in files {
            guard Self.isSafeRelativePath(file.path), Self.isSHA256Hex(file.sha256), file.size >= 0 else {
                throw ModelInstallError.invalidManifest
            }
        }
        guard Set(files.map(\.path)).count == files.count else { throw ModelInstallError.invalidManifest }
        guard (0...Self.maximumTotalSize).contains(totalSize), Self.checkedSum(files.map(\.size)) == totalSize else {
            throw ModelInstallError.invalidManifest
        }
        guard let modelFormat else { throw ModelInstallError.invalidManifest }
        if let minimum = minimumOS?.macOS {
            guard let minimumVersion = SemanticVersion(minimum), system >= minimumVersion else { throw ModelInstallError.invalidManifest }
        }
        switch modelFormat {
        case .packages:
            break
        case .compiled:
            // Compiled models load only from the macOS they were compiled for, so that has to be stated.
            guard minimumOS?.macOS != nil,
                  packageNames.isEmpty,
                  Set(PianissimoModel.requiredModelNames).isSubset(of: compiledModelNames)
            else { throw ModelInstallError.invalidManifest }
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
