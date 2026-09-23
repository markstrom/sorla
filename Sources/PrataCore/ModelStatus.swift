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
        case .notInstalled: return "Not installed"
        case .installed(let version): return version.map { "Version \($0)" } ?? "Installed"
        case .checking: return "Checking for updates…"
        case .upToDate(let version): return "Up to date · Version \(version)"
        case .updateAvailable(let version): return "Update available · Version \(version)"
        case .downloading(_, let fraction, _): return "Downloading \(Self.percent(fraction))%"
        case .preparing: return "Preparing…"
        case .waitingToInstall: return "Installing when dictation ends…"
        case .failed(let error, _), .checkFailed(let error): return "Failed: \(error.reason)"
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
