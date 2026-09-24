import Combine
import Foundation
import os

@MainActor
public final class ModelManager: ObservableObject {
    @Published public private(set) var status: ModelStatus = .notInstalled

    public var automaticChecks: Bool {
        didSet {
            guard hasStarted, automaticChecks != oldValue else { return }
            scheduleAutomaticChecks(checkFirst: automaticChecks)
        }
    }
    public var automaticDownloads: Bool
    public var onInstalled: ((_ wasFirstInstall: Bool) -> Void)?
    public var onFailure: ((SorlaIssue) -> Void)?
    // Lets the app update check ride on this timer instead of waking the Mac on its own.
    public var onAutomaticCheck: (() -> Void)?

    private let installer: ModelInstaller
    private let swap: ModelSwap
    private let failedUpdate: FailedModelUpdate
    private let isDictationIdle: @MainActor () -> Bool
    private let reloadModel: @MainActor () async -> Bool
    private let checkInterval: TimeInterval
    private let idlePollInterval: TimeInterval
    private var hasStarted = false
    private var work: Task<Void, Never>?
    private var automaticCheckTask: Task<Void, Never>?
    private var offered: PublishedModel?
    private var stagingVersion: String?
    private static let logger = Logger(subsystem: "com.sorla.app", category: "ModelManager")

    public init(
        installer: ModelInstaller,
        isDictationIdle: @escaping @MainActor () -> Bool,
        reloadModel: @escaping @MainActor () async -> Bool,
        automaticChecks: Bool,
        automaticDownloads: Bool,
        checkInterval: TimeInterval = 24 * 60 * 60,
        idlePollInterval: TimeInterval = 0.5
    ) {
        self.installer = installer
        self.swap = ModelSwap(modelsDirectory: installer.modelsDirectory)
        self.failedUpdate = FailedModelUpdate(modelsDirectory: installer.modelsDirectory)
        self.isDictationIdle = isDictationIdle
        self.reloadModel = reloadModel
        self.automaticChecks = automaticChecks
        self.automaticDownloads = automaticDownloads
        self.checkInterval = checkInterval
        self.idlePollInterval = idlePollInterval
    }

    public var isInstalled: Bool { PianissimoModel.hasRequiredFiles(at: swap.installed) }

    public var installedVersion: String? { PianissimoModel.installedVersion(at: swap.installed) }

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        recoverInterruptedSwap()
        let installed = isInstalled
        let version = installedVersion
        Self.logger.info("model manager started: installed=\(installed, privacy: .public) version=\(version ?? "unknown", privacy: .public) automaticChecks=\(self.automaticChecks, privacy: .public) automaticDownloads=\(self.automaticDownloads, privacy: .public)")
        if installed {
            removeUnneededStaging(installedVersion: version)
        }
        status = installed ? .installed(version: version) : .notInstalled
        switch ModelUpdatePolicy.launchAction(isInstalled: installed, autoCheck: automaticChecks) {
        case .none:
            break
        case .check:
            scheduleAutomaticChecks(checkFirst: true)
        case .install:
            downloadModel()
            if automaticChecks { scheduleAutomaticChecks(checkFirst: false) }
        }
    }

    public func checkNow() {
        check(userInitiated: true)
    }

    private func check(userInitiated: Bool) {
        guard work == nil else { return }
        guard isInstalled else { return downloadModel() }
        status = .checking
        Self.logger.info("model update check started")
        work = Task {
            defer { self.work = nil }
            let latest: PublishedModel
            do {
                latest = try await self.fetchLatest()
            } catch {
                let checkError = error as? ModelInstallError ?? .network
                Self.logger.error("model update check failed: \(String(describing: checkError), privacy: .public)")
                self.status = .checkFailed(checkError)
                return
            }
            let decision = ModelUpdatePolicy.decide(
                installedVersion: self.installedVersion,
                isInstalled: true,
                latest: latest.release,
                autoDownload: self.automaticDownloads,
                failedVersion: userInitiated ? nil : self.failedUpdate.version
            )
            Self.logger.info("model update check: installed \(self.installedVersion ?? "unknown", privacy: .public), latest \(latest.release.version, privacy: .public), decision \(String(describing: decision), privacy: .public)")
            switch decision {
            case .none:
                self.status = self.installedVersion.map { .upToDate(version: $0) } ?? .installed(version: nil)
            case .notify(let version):
                self.offered = latest
                self.status = .updateAvailable(version: version)
            case .download:
                await self.install(latest, isUpdate: true)
            }
        }
    }

    // Installs the latest model: the first install, a retry, or an update the user accepted.
    public func downloadModel() {
        guard work == nil else { return }
        let isUpdate = isInstalled
        status = .downloading(version: offered?.release.version ?? "", fraction: 0, isUpdate: isUpdate)
        work = Task {
            defer { self.work = nil }
            let latest: PublishedModel
            if let offered = self.offered {
                latest = offered
            } else {
                do {
                    latest = try await self.fetchLatest()
                } catch {
                    self.fail(error, isUpdate: isUpdate)
                    return
                }
            }
            let decision = ModelUpdatePolicy.decide(installedVersion: self.installedVersion, isInstalled: isUpdate, latest: latest.release, autoDownload: true)
            guard case .download = decision else {
                Self.logger.info("model \(latest.release.version, privacy: .public) is already installed")
                self.offered = nil
                self.status = self.installedVersion.map { .upToDate(version: $0) } ?? .notInstalled
                return
            }
            await self.install(latest, isUpdate: isUpdate)
        }
    }

    // Loads the installed model again after it failed to load, first finishing any swap that was cut short.
    public func retryLoadingModel() {
        guard work == nil else { return }
        work = Task {
            defer { self.work = nil }
            self.recoverInterruptedSwap()
            guard self.isInstalled else {
                self.status = .notInstalled
                return
            }
            Self.logger.info("retrying to load the installed model")
            if await !self.reloadModel() {
                Self.logger.error("installed model failed to load again")
                self.onFailure?(.modelNotLoaded)
            }
        }
    }

    private func recoverInterruptedSwap() {
        do {
            if let discarded = try swap.recoverInterruptedSwap() {
                Self.logger.info("rolled back unconfirmed model \(discarded, privacy: .public)")
                rememberFailure(of: discarded)
            }
        } catch {
            Self.logger.error("couldn't recover an interrupted model swap: \(ErrorSummary.of(error), privacy: .public)")
        }
    }

    private func fetchLatest() async throws -> PublishedModel {
        let installer = self.installer
        return try await Task.detached(priority: .utility) { try await installer.fetchLatest() }.value
    }

    private func install(_ latest: PublishedModel, isUpdate: Bool) async {
        let version = latest.release.version
        Self.logger.info("model download started: \(version, privacy: .public) (\(isUpdate ? "update" : "first install", privacy: .public))")
        status = .downloading(version: version, fraction: 0, isUpdate: isUpdate)
        stagingVersion = version
        let installer = self.installer
        let report: @Sendable (ModelInstallProgress) -> Void = { [weak self] progress in
            Task { @MainActor in self?.apply(progress, version: version, isUpdate: isUpdate) }
        }
        let staged: URL
        do {
            staged = try await Task.detached(priority: .utility) {
                try await installer.stage(latest, progress: report)
            }.value
            stagingVersion = nil
        } catch {
            stagingVersion = nil
            rememberFailure(of: version, after: error)
            fail(error, isUpdate: isUpdate)
            return
        }

        if !isDictationIdle() {
            Self.logger.info("model \(version, privacy: .public) staged; waiting for dictation to finish")
            status = .waitingToInstall(version: version)
            while !isDictationIdle() {
                try? await Task.sleep(nanoseconds: UInt64(idlePollInterval * 1_000_000_000))
            }
        }

        let replacedModel: Bool
        do {
            replacedModel = try swap.install(staged)
        } catch {
            rememberFailure(of: version, after: error)
            fail(error, isUpdate: isUpdate)
            return
        }
        Self.logger.info("model \(version, privacy: .public) swapped in; loading it")
        guard await reloadModel() else {
            await handleReloadFailure(version: version, replacedModel: replacedModel)
            return
        }
        commitSwap()
        do {
            try failedUpdate.clear()
        } catch {
            Self.logger.error("couldn't clear the failed model version: \(ErrorSummary.of(error), privacy: .public)")
        }
        removeStaging(version: version)
        offered = nil
        status = .upToDate(version: version)
        Self.logger.info("model \(version, privacy: .public) installed and ready")
        onInstalled?(!replacedModel)
    }

    // A self-tested first install stays; an update rolls back but keeps its downloads so a retry needn't refetch.
    private func handleReloadFailure(version: String, replacedModel: Bool) async {
        guard replacedModel else {
            Self.logger.error("new model \(version, privacy: .public) failed to load; keeping it installed")
            commitSwap()
            removeStaging(version: version)
            offered = nil
            status = .installed(version: version)
            onFailure?(.modelNotLoaded)
            return
        }
        Self.logger.error("model update \(version, privacy: .public) failed to load; rolling back")
        rememberFailure(of: version)
        var rolledBack = true
        do {
            try swap.rollback()
        } catch {
            Self.logger.error("model rollback failed: \(ErrorSummary.of(error), privacy: .public)")
            do {
                try swap.recoverInterruptedSwap()
            } catch {
                Self.logger.error("couldn't recover after the failed rollback: \(ErrorSummary.of(error), privacy: .public)")
                rolledBack = false
            }
        }
        let previousLoaded = rolledBack ? await reloadModel() : false
        if !previousLoaded {
            Self.logger.error("previous model isn't loaded after the failed update")
        }
        fail(ModelInstallError.installFailed, isUpdate: true, previousModelWorks: previousLoaded)
    }

    private func commitSwap() {
        do {
            try swap.commit()
        } catch {
            Self.logger.error("couldn't remove the previous model: \(ErrorSummary.of(error), privacy: .public)")
        }
    }

    // Failures a later attempt may not repeat are retried automatically; the rest wait for the user.
    private func rememberFailure(of version: String, after error: Error? = nil) {
        if let error {
            if error is CancellationError { return }
            switch error as? ModelInstallError {
            case .network, .serverUnavailable, .diskWriteFailed, .insufficientDiskSpace: return
            default: break
            }
        }
        do {
            try failedUpdate.record(version)
        } catch {
            Self.logger.error("couldn't remember the failed model version: \(ErrorSummary.of(error), privacy: .public)")
        }
    }

    private func removeStaging(version: String) {
        do {
            try ModelStaging(modelsDirectory: installer.modelsDirectory, version: version).removeAll()
            Self.logger.info("removed staging for \(version, privacy: .public)")
        } catch {
            Self.logger.error("couldn't remove staging for \(version, privacy: .public): \(ErrorSummary.of(error), privacy: .public)")
        }
    }

    // Only automatic checks with automatic downloads resume a leftover update, and never one that failed here.
    private func removeUnneededStaging(installedVersion: String?) {
        let modelsDirectory = installer.modelsDirectory
        var removed = automaticChecks && automaticDownloads
            ? ModelStaging.removeStale(in: modelsDirectory, installedVersion: installedVersion)
            : ModelStaging.removeEverything(in: modelsDirectory)
        if let failedVersion = failedUpdate.version {
            let staging = ModelStaging(modelsDirectory: modelsDirectory, version: failedVersion)
            if FileManager.default.fileExists(atPath: staging.directory.path), (try? staging.removeAll()) != nil {
                removed.append(staging.directory.lastPathComponent)
            }
        }
        if !removed.isEmpty {
            Self.logger.info("removed unneeded staging: \(removed.joined(separator: ", "), privacy: .public)")
        }
    }

    private func apply(_ progress: ModelInstallProgress, version: String, isUpdate: Bool) {
        guard stagingVersion == version,
              let next = Self.status(after: status, applying: progress, version: version, isUpdate: isUpdate)
        else { return }
        status = next
    }

    // Progress reports hop to the main actor one by one and may arrive out of order, so they only move forward.
    static func status(after current: ModelStatus, applying progress: ModelInstallProgress, version: String, isUpdate: Bool) -> ModelStatus? {
        switch progress {
        case .downloading(let fraction):
            switch current {
            case .preparing:
                return nil
            case .downloading(_, let shown, _) where ModelStatus.percent(fraction) <= ModelStatus.percent(shown):
                return nil
            default:
                return .downloading(version: version, fraction: fraction, isUpdate: isUpdate)
            }
        case .preparing:
            return .preparing(version: version, isUpdate: isUpdate)
        }
    }

    // An update failure only says the current model stays in use when it really is loaded.
    private func fail(_ error: Error, isUpdate: Bool, previousModelWorks: Bool = true) {
        let installError = error as? ModelInstallError ?? .installFailed
        Self.logger.error("model install failed: \(String(describing: installError), privacy: .public)")
        status = .failed(installError, isUpdate: isUpdate)
        let issue: SorlaIssue = !isUpdate ? .modelDownloadFailed : previousModelWorks ? .modelUpdateFailed : .modelNotLoaded
        onFailure?(issue)
    }

    private func scheduleAutomaticChecks(checkFirst: Bool) {
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
        guard automaticChecks else { return }
        let interval = UInt64(checkInterval * 1_000_000_000)
        automaticCheckTask = Task { [weak self] in
            var checkNext = checkFirst
            while !Task.isCancelled {
                if !checkNext {
                    try? await Task.sleep(nanoseconds: interval)
                }
                checkNext = false
                guard !Task.isCancelled, let self else { return }
                self.onAutomaticCheck?()
                self.check(userInitiated: false)
            }
        }
    }
}
