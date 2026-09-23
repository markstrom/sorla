import Foundation

public enum ModelInstallError: Error, Equatable, Sendable {
    case invalidManifest
    case network
    case insufficientDiskSpace(required: Int64)
    case verificationFailed(path: String)
    case compileFailed
    case selfTestFailed
    case installFailed

    public var reason: String {
        switch self {
        case .invalidManifest: return "The model list couldn't be read."
        case .network: return "Couldn't reach Hugging Face. Check your internet connection."
        case .insufficientDiskSpace(let required): return "Not enough disk space (\(Self.gigabytes(required)) free needed)."
        case .verificationFailed: return "A downloaded file was damaged."
        case .compileFailed: return "The model couldn't be prepared for this Mac."
        case .selfTestFailed: return "The new model didn't pass its self-test."
        case .installFailed: return "The new model couldn't be installed."
        }
    }

    private static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}
