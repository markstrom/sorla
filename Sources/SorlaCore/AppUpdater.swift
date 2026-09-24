import Combine
import Foundation
import os

public enum AppInstallState: Equatable, Sendable {
    case idle
    // Downloaded and verified in the background, waiting for a quiet moment.
    case ready(version: String)
    case installing(version: String)
    case failed(version: String, AppInstallFailure)
}

// The shared defaults outlive the swap, so the new Sorla reads what the old one wrote.
public struct AppInstallJournal {
    private let defaults: UserDefaults
    private static let recordKey = "appInstallRecord"
    private static let pendingKey = "pendingAppUpdate"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var record: AppInstallRecord? {
        get { read(Self.recordKey) }
        nonmutating set { write(newValue, Self.recordKey) }
    }

    // A release that automatic install found but hadn't installed when Sorla quit.
    public var pendingRelease: PinnedRelease? {
        get { read(Self.pendingKey) }
        nonmutating set { write(newValue, Self.pendingKey) }
    }

    private func read<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func write<T: Encodable>(_ value: T?, _ key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

@MainActor
public final class AppUpdater: ObservableObject {
    @Published public private(set) var state: AppInstallState = .idle
    public let location: AppInstallLocation
    public var automaticChecks: Bool
    public var automaticInstalls: Bool {
        didSet {
            guard automaticInstalls != oldValue else { return }
            if case .ready = state { scheduleAutomaticInstall(atLaunch: false) }
        }
    }
    public var onUpdated: ((String) -> Void)?

    private let installer: AppInstaller
    private let relauncher: AppRelaunching
    private let journal: AppInstallJournal
    private let activity: @MainActor () -> DictationActivity
    // Returns whether quitting went ahead; NSApp.terminate only comes back when it was called off.
    private let terminate: @MainActor () -> Bool
    private let isAppReplaced: @MainActor () -> Bool
    private let processID: Int32
    private let pollInterval: Duration
    private let sleep: @MainActor (Duration) async -> Void
    private let now: @MainActor () -> Date
    private var prepared: PreparedAppUpdate?
    private var lastActivity: Date
    private(set) var work: Task<Void, Never>?
    private var workID = 0
    private(set) var automaticWait: Task<Void, Never>?
    private(set) var backupRemoval: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.sorla.app", category: "AppUpdater")

    public init(
        installer: AppInstaller,
        location: AppInstallLocation,
        relauncher: AppRelaunching,
        journal: AppInstallJournal,
        automaticChecks: Bool,
        automaticInstalls: Bool,
        activity: @escaping @MainActor () -> DictationActivity,
        terminate: @escaping @MainActor () -> Bool,
        isAppReplaced: @escaping @MainActor () -> Bool = { false },
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        pollInterval: Duration = .milliseconds(500),
        sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.installer = installer
        self.location = location
        self.relauncher = relauncher
        self.journal = journal
        self.automaticChecks = automaticChecks
        self.automaticInstalls = automaticInstalls
        self.activity = activity
        self.terminate = terminate
        self.isAppReplaced = isAppReplaced
        self.processID = processID
        self.pollInterval = pollInterval
        self.sleep = sleep
        self.now = now
        self.lastActivity = now()
    }

    private var isAutomatic: Bool {
        AutomaticAppInstall.isEnabled(autoCheck: automaticChecks, autoInstall: automaticInstalls)
    }

    // At launch: finish an install that relaunched into this Sorla, clear leftovers, and take up an automatic install.
    public func start() {
        let record = journal.record
        switch AppInstallRecovery.atLaunch(record: record, bundlePath: installer.bundleURL.path, runningVersion: installer.runningVersion) {
        case .none:
            break
        case .keepBackup:
            Self.logger.info("an earlier install's backup is kept: this Sorla runs from elsewhere")
        case .removeBackupAfterGrace(let updatedTo):
            if let updatedTo {
                Self.logger.info("relaunched into \(updatedTo, privacy: .public)")
                onUpdated?(updatedTo)
            }
            scheduleBackupRemoval(record)
        }
        if let pending = journal.pendingRelease, !Self.isNewer(pending.version, than: installer.runningVersion) {
            journal.pendingRelease = nil
        }
        let installer = self.installer
        run {
            await installer.removeLeftovers()
            guard let pending = self.journal.pendingRelease, self.isAutomatic, self.location.canInstall else { return }
            Self.logger.info("taking up the automatic install of \(pending.version, privacy: .public) at launch")
            self.prepareAutomatically(pending, atLaunch: true)
        }
    }

    public func dictationActivityChanged() {
        lastActivity = now()
    }

    // A check found a newer Sorla; with both toggles on, it is fetched and checked in the background.
    public func updateFound(_ pin: PinnedRelease?, automatic: Bool) {
        if case .failed = state { state = .idle }
        guard let pin, automatic, isAutomatic, location.canInstall else { return }
        switch state {
        case .installing: return
        case .ready(let version) where version == pin.version: return
        default: break
        }
        journal.pendingRelease = pin
        prepareAutomatically(pin, atLaunch: false)
    }

    // Install and Relaunch: now, or as soon as the dictation in flight has landed.
    public func install(_ pin: PinnedRelease) {
        guard location.canInstall else { return }
        if case .installing = state { return }
        automaticWait?.cancel()
        automaticWait = nil
        state = .installing(version: pin.version)
        run {
            do {
                let prepared = try await self.prepared(for: pin)
                let staged = try await self.stage(prepared)
                while !self.activity().isQuiet {
                    await self.sleep(self.pollInterval)
                }
                try self.swapAndRelaunch(staged)
            } catch {
                self.fail(error, version: pin.version)
            }
        }
    }

    // One piece of work at a time, each after the last, so a click during a background download reuses it.
    private func run(_ body: @escaping @MainActor () async -> Void) {
        let previous = work
        workID += 1
        let id = workID
        work = Task {
            await previous?.value
            await body()
            if self.workID == id { self.work = nil }
        }
    }

    // A click on Install and Relaunch meanwhile owns the state and reports its own outcome.
    private func prepareAutomatically(_ pin: PinnedRelease, atLaunch: Bool) {
        run {
            do {
                _ = try await self.prepared(for: pin)
            } catch {
                if case .installing = self.state { return }
                self.fail(error, version: pin.version)
                return
            }
            if case .installing = self.state { return }
            self.state = .ready(version: pin.version)
            self.scheduleAutomaticInstall(atLaunch: atLaunch)
        }
    }

    // Sleeps until the quiet period would be up, and looks again, so nothing runs in between.
    private func scheduleAutomaticInstall(atLaunch: Bool) {
        automaticWait?.cancel()
        automaticWait = Task {
            var atLaunch = atLaunch
            while !Task.isCancelled {
                let decision = AutomaticAppInstall.decide(
                    autoCheck: self.automaticChecks,
                    autoInstall: self.automaticInstalls,
                    atLaunch: atLaunch,
                    lastActivity: self.lastActivity,
                    now: self.now(),
                    isQuiet: self.activity().isQuiet
                )
                switch decision {
                case .never:
                    self.automaticWait = nil
                    return
                case .now:
                    self.automaticWait = nil
                    self.installAutomatically()
                    return
                case .after(let seconds):
                    await self.sleep(.seconds(seconds))
                    atLaunch = false
                }
            }
        }
    }

    private func installAutomatically() {
        guard case .ready(let version) = state, let prepared else { return }
        state = .installing(version: version)
        run {
            do {
                let staged = try await self.stage(prepared)
                // A dictation that began while copying wins; the install waits for the next quiet stretch.
                guard self.activity().isQuiet else {
                    self.installer.discard(staged)
                    self.state = .ready(version: version)
                    self.scheduleAutomaticInstall(atLaunch: false)
                    return
                }
                try self.swapAndRelaunch(staged)
            } catch {
                self.fail(error, version: version)
            }
        }
    }

    private func prepared(for pin: PinnedRelease) async throws -> PreparedAppUpdate {
        if let prepared, prepared.version == pin.version, installer.isAvailable(prepared) { return prepared }
        if let prepared { installer.discard(prepared) }
        prepared = nil
        let installer = self.installer
        let result = try await Task.detached(priority: .utility) { try await installer.prepare(pin) }.value
        prepared = result
        return result
    }

    private func stage(_ prepared: PreparedAppUpdate) async throws -> StagedAppUpdate {
        guard !isAppReplaced() else { throw AppInstallError.replacedOnDisk }
        let installer = self.installer
        return try await Task.detached(priority: .userInitiated) { try installer.stage(prepared) }.value
    }

    // Runs without a suspension point from the quiet check to the quit, so no dictation can start in between.
    private func swapAndRelaunch(_ staged: StagedAppUpdate) throws {
        // A rebuild with the same version is only told apart by the running app's own check.
        if isAppReplaced() {
            installer.discard(staged)
            throw AppInstallError.replacedOnDisk
        }
        prepared = nil
        let record = try installer.swap(staged)
        journal.record = record
        do {
            try relauncher.start(waitingFor: processID, thenOpen: installer.bundleURL, expectedVersion: record.version)
        } catch {
            undo(record)
            throw AppInstallError.relaunch
        }
        Self.logger.info("relaunching into \(record.version, privacy: .public)")
        guard !terminate() else { return }
        Self.logger.error("quitting was called off; putting the previous app back")
        relauncher.cancel()
        undo(record)
        throw AppInstallError.relaunch
    }

    private func undo(_ record: AppInstallRecord) {
        installer.rollBack(record)
        journal.record = nil
    }

    private func scheduleBackupRemoval(_ record: AppInstallRecord?) {
        guard let record else { return }
        backupRemoval = Task {
            await self.sleep(.seconds(AppInstallRecovery.grace))
            self.installer.removeBackup(of: record)
            self.journal.record = nil
            self.backupRemoval = nil
            Self.logger.info("removed the previous app's backup")
        }
    }

    private func fail(_ error: Error, version: String) {
        let installError = error as? AppInstallError ?? .download
        if let prepared, installError.failure != .relaunch {
            installer.discard(prepared)
            self.prepared = nil
        }
        // Not a failure to show: the menu already offers the restart into the Sorla that is on disk now.
        if installError == .replacedOnDisk {
            Self.logger.info("app update \(version, privacy: .public) not installed: Sorla.app was replaced meanwhile")
            state = .idle
            return
        }
        journal.pendingRelease = nil
        Self.logger.error("app update \(version, privacy: .public) not installed: \(String(describing: installError), privacy: .public)")
        state = .failed(version: version, installError.failure)
    }

    static func isNewer(_ version: String, than running: String?) -> Bool {
        guard let candidate = SemanticVersion(version), let current = running.flatMap(SemanticVersion.init) else { return false }
        return candidate > current
    }
}
