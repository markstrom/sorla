import Foundation

public enum ModelInstallError: Error, Equatable, Sendable {
    case invalidManifest
    case network
    case serverUnavailable
    case diskWriteFailed
    case insufficientDiskSpace(required: Int64)
    case verificationFailed(path: String)
    case compileFailed
    case selfTestFailed
    case installFailed

    public var reason: String {
        switch self {
        case .invalidManifest: return String(localized: "The model list couldn't be read.", bundle: Localization.bundle)
        case .network: return String(localized: "Couldn't reach Hugging Face. Check your internet connection.", bundle: Localization.bundle)
        case .serverUnavailable: return String(localized: "Hugging Face couldn't provide the model right now. Try again later.", bundle: Localization.bundle)
        case .diskWriteFailed: return String(localized: "The model files couldn't be saved. Check that there's free disk space.", bundle: Localization.bundle)
        case .insufficientDiskSpace(let required): return String(localized: "Not enough disk space (\(Self.gigabytes(required)) free needed).", bundle: Localization.bundle)
        case .verificationFailed: return String(localized: "A downloaded file was damaged.", bundle: Localization.bundle)
        case .compileFailed: return String(localized: "The model couldn't be prepared for this Mac.", bundle: Localization.bundle)
        case .selfTestFailed: return String(localized: "The new model didn't pass its self-test.", bundle: Localization.bundle)
        case .installFailed: return String(localized: "The new model couldn't be installed.", bundle: Localization.bundle)
        }
    }

    private static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.1f GB", locale: Localization.locale, Double(bytes) / 1_000_000_000)
    }
}
