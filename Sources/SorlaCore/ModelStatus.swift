import Foundation

public enum ModelStatus: Equatable, Sendable {
    case notInstalled
    case installed(version: String?)
    case checking
    case upToDate(version: String)
    case updateAvailable(version: String)
    case downloading(version: String, fraction: Double, isUpdate: Bool)
    case preparing(version: String, isUpdate: Bool)
    case waitingToInstall(version: String)
    case failed(ModelInstallError, isUpdate: Bool)
    case checkFailed(ModelInstallError)

    public var settingsText: String {
        switch self {
        case .notInstalled: return String(localized: "Not installed", bundle: Localization.bundle)
        case .installed(let version): return version.map { String(localized: "Version \($0)", bundle: Localization.bundle) } ?? String(localized: "Installed", bundle: Localization.bundle)
        case .checking: return String(localized: "Checking for updates…", bundle: Localization.bundle)
        case .upToDate(let version): return String(localized: "Up to date · Version \(version)", bundle: Localization.bundle)
        case .updateAvailable(let version): return String(localized: "Update available · Version \(version)", bundle: Localization.bundle)
        case .downloading(_, let fraction, _): return String(localized: "Downloading \(Self.percent(fraction))%", bundle: Localization.bundle)
        case .preparing: return String(localized: "Preparing… ~1 min", bundle: Localization.bundle)
        case .waitingToInstall: return String(localized: "Installing when dictation ends…", bundle: Localization.bundle)
        case .failed(let error, _), .checkFailed(let error): return String(localized: "Failed: \(error.reason)", bundle: Localization.bundle)
        }
    }

    public var isBusy: Bool {
        switch self {
        case .checking, .downloading, .preparing, .waitingToInstall: return true
        default: return false
        }
    }

    static func percent(_ fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded(.down))
    }
}
