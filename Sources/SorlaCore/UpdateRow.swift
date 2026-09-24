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
        case install
    }

    public let text: String?
    public let kind: Kind
    public let action: Action?
    // A line under the row saying why the usual action isn't offered, or what to do instead.
    public let note: String?

    public init(text: String?, kind: Kind = .plain, action: Action? = nil, note: String? = nil) {
        self.text = text
        self.kind = kind
        self.action = action
        self.note = note
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

    // A failed check or install says why and never reads as "Latest".
    public static func app(_ status: AppUpdateStatus, offer: AppUpdateOffer? = nil) -> UpdateRow {
        switch offer {
        case .install(let version):
            return UpdateRow(text: available(version).text, action: .install)
        case .download(let version, let note):
            return UpdateRow(text: available(version).text, action: .download, note: note)
        case .homebrew(let version):
            let note = String(localized: "Update with Homebrew: \(AppUpdateOffer.homebrewCommand)", bundle: Localization.bundle)
            return UpdateRow(text: available(version).text, note: note)
        case .installing:
            return UpdateRow(text: String(localized: "Installing…", bundle: Localization.bundle), kind: .busy)
        case .failed(_, let failure):
            return UpdateRow(text: failure.message, kind: .failure, action: .download)
        case nil:
            break
        }
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
    public static func canCheckNow(app: AppUpdateStatus, model: ModelStatus, install: AppInstallState = .idle) -> Bool {
        guard app != .checking, !model.isBusy else { return false }
        if case .installing = install { return false }
        return true
    }
}
