import Foundation

// One row in Settings › Updates: the version, then what the last check or install says about it.
public struct UpdateRow: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case plain
        case busy
        case latest
        case failure
    }

    public enum Action: Equatable, Sendable {
        case download
        case tryAgain
    }

    public let text: String?
    public let kind: Kind
    public let action: Action?

    public init(text: String?, kind: Kind = .plain, action: Action? = nil) {
        self.text = text
        self.kind = kind
        self.action = action
    }

    private static var latest: UpdateRow {
        UpdateRow(text: String(localized: "Latest", bundle: Localization.bundle), kind: .latest)
    }

    private static var checking: UpdateRow {
        UpdateRow(text: String(localized: "Checking…", bundle: Localization.bundle), kind: .busy)
    }

    private static func available(_ version: String) -> UpdateRow {
        UpdateRow(text: String(localized: "\(version) available", bundle: Localization.bundle), action: .download)
    }

    // A failed check says why and never reads as "Latest".
    public static func app(_ status: AppUpdateStatus) -> UpdateRow {
        switch status {
        case .notChecked: return UpdateRow(text: nil)
        case .checking: return checking
        case .upToDate: return latest
        case .available(let version): return available(version)
        case .failed(let failure): return UpdateRow(text: failure.message, kind: .failure)
        }
    }

    public static func model(_ status: ModelStatus) -> UpdateRow {
        switch status {
        case .notInstalled: return UpdateRow(text: status.settingsText, action: .download)
        case .installed: return UpdateRow(text: nil)
        case .checking: return checking
        case .upToDate: return latest
        case .updateAvailable(let version): return available(version)
        case .downloading, .preparing, .waitingToInstall: return UpdateRow(text: status.settingsText, kind: .busy)
        case .failed: return UpdateRow(text: status.settingsText, kind: .failure, action: .tryAgain)
        case .checkFailed: return UpdateRow(text: status.settingsText, kind: .failure)
        }
    }

    // Check Now waits while either half is still busy, so one click never starts a second check.
    public static func canCheckNow(app: AppUpdateStatus, model: ModelStatus) -> Bool {
        app != .checking && !model.isBusy
    }
}
