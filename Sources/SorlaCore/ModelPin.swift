import CryptoKit
import Foundation

// One exact model release, fixed when Sorla is built: the manifest's checksum fixes every file through its hashes.
// Files are fetched relative to the manifest's folder at the same commit, never from a branch that can move.
public struct ModelPin: Equatable, Sendable {
    public let version: String
    public let manifestURL: URL
    public let manifestSHA256: String

    public init(version: String, manifestURL: URL, manifestSHA256: String) {
        self.version = version
        self.manifestURL = manifestURL
        self.manifestSHA256 = manifestSHA256
    }

    public var filesBaseURL: URL { manifestURL.deletingLastPathComponent() }

    public func fileURL(for path: String) -> URL {
        filesBaseURL.appendingPathComponent(path)
    }

    public func matches(_ manifestData: Data) -> Bool {
        SHA256.hash(data: manifestData).map { String(format: "%02x", $0) }.joined() == manifestSHA256
    }

    static let repository = URL(string: "https://huggingface.co/markstrom/pianissimo-sv-coreml/resolve")!

    // Tag 1.0.0: Core ML packages that Sorla compiles on the Mac; works on every macOS Sorla supports.
    public static let packages = ModelPin(
        version: "1.0.0",
        manifestURL: repository.appendingPathComponent("106fa163a138a0db6737e0c50494269e07f508d0/manifest.json"),
        manifestSHA256: "f83d4f6000290c88d2b52d5eeda648065d24ffb5cb1ad1f1aaaee3f85e61868a"
    )

    // Tag 1.1.0-compiled: the same weights compiled ahead for macOS 26, so nothing is compiled on the Mac.
    public static let compiled = ModelPin(
        version: "1.1.0",
        manifestURL: repository.appendingPathComponent("dd578628d1ae6577b4672221b99fff59112ff5b4/compiled/1.1.0/manifest.json"),
        manifestSHA256: "8c88cff874bc277c9210cc55f8f47d72859ca2983b764e73e0ff7ad0ad96767e"
    )

    // The compiled release's own `minimumOS`; its manifest is checked against the running system as well.
    public static let compiledMinimumSystem = SemanticVersion(major: 26, minor: 0, patch: 0)

    public static func choose(for system: SemanticVersion, packages: ModelPin, compiled: ModelPin) -> ModelPin {
        system >= compiledMinimumSystem ? compiled : packages
    }

    public static func forSystem(_ system: SemanticVersion) -> ModelPin {
        choose(for: system, packages: packages, compiled: compiled)
    }

    public static var current: ModelPin { forSystem(.runningSystem) }
}

extension SemanticVersion {
    public static var runningSystem: SemanticVersion {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return SemanticVersion(major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion)
    }
}
