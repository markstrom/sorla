import Combine
import Foundation

public enum AppUpdateStatus: Equatable, Sendable {
    case notChecked
    case checking
    case upToDate
    case available(version: String)
    case failed(AppUpdateFailure)

    public init(_ result: AppUpdateResult) {
        switch result {
        case .upToDate: self = .upToDate
        case .available(let version): self = .available(version: version)
        case .failed(let failure): self = .failed(failure)
        }
    }

    public var availableVersion: String? {
        if case .available(let version) = self { return version }
        return nil
    }
}

public enum AppUpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60
    // The daily timer may fire a little early, and "about once a day" is all that's promised.
    static let tolerance: TimeInterval = 60 * 60

    public static func isDue(automaticChecks: Bool, lastCheck: Date?, now: Date) -> Bool {
        guard automaticChecks else { return false }
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed < 0 || elapsed >= interval - tolerance
    }
}

// One check covers Sorla (GitHub) and the speech model (Hugging Face), whether asked for or automatic.
@MainActor
public final class UpdateChecker: ObservableObject {
    @Published public private(set) var appStatus: AppUpdateStatus = .notChecked
    // Set with a newer version when its release carries the DMG an install needs.
    public private(set) var pinnedRelease: PinnedRelease?
    public var automaticChecks: Bool
    public var onAppCheckFinished: ((_ automatic: Bool) -> Void)?

    private let currentVersion: String?
    private let source: AppReleaseSource
    private let defaults: UserDefaults
    private let checkModel: @MainActor () -> Void
    private let now: () -> Date
    private(set) var appCheck: Task<Void, Never>?

    private static let lastCheckKey = "lastAppUpdateCheck"

    public init(
        currentVersion: String?,
        source: AppReleaseSource,
        automaticChecks: Bool,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        checkModel: @escaping @MainActor () -> Void
    ) {
        self.currentVersion = currentVersion
        self.source = source
        self.automaticChecks = automaticChecks
        self.defaults = defaults
        self.now = now
        self.checkModel = checkModel
    }

    public var lastAppCheck: Date? {
        defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    public func checkNow() {
        checkApp(automatic: false)
        checkModel()
    }

    // The model's launch check reads this too, so both follow the same persisted date.
    public var isAutomaticCheckDue: Bool {
        AppUpdateSchedule.isDue(automaticChecks: automaticChecks, lastCheck: lastAppCheck, now: now())
    }

    // Called at launch and on the model's daily check, so the app check adds no timer of its own.
    public func checkAppIfDue() {
        guard isAutomaticCheckDue else { return }
        checkApp(automatic: true)
    }

    private func checkApp(automatic: Bool) {
        guard appStatus != .checking else { return }
        defaults.set(now(), forKey: Self.lastCheckKey)
        appStatus = .checking
        let currentVersion = self.currentVersion
        let source = self.source
        appCheck = Task {
            let (result, pin) = await AppUpdateCheck.checkPinning(currentVersion: currentVersion, source: source)
            self.pinnedRelease = pin
            self.appStatus = AppUpdateStatus(result)
            self.appCheck = nil
            self.onAppCheckFinished?(automatic)
        }
    }
}
