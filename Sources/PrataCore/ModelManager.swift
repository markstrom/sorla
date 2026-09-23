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
    public var onFailure: ((PrataIssue) -> Void)?

    private let installer: ModelInstaller
    private let swap: ModelSwap
    private let isDictationIdle: @MainActor () -> Bool
    private let reloadModel: @MainActor () async -> Bool
    private let checkInterval: TimeInterval
    private let idlePollInterval: TimeInterval
    private var hasStarted = false
    private var work: Task<Void, Never>?
    private var automaticCheckTask: Task<Void, Never>?
    private var offered: PublishedModel?
    private var stagingVersion: String?
    private static let logger = Logger(subsystem: "com.prata.app", category: "ModelManager")

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
        self.isDictationIdle = isDictationIdle
        self.reloadModel = reloadModel
        self.automaticChecks = automaticChecks
        self.automaticDownloads = automaticDownloads
        self.checkInterval = checkInterval
        self.idlePollInterval = idlePollInterval
    }

    public var isInstalled: Bool { PianissimoModel.hasRequiredFiles(at: swap.installed) }

    private var installedVersion: String? { PianissimoModel.installedVersion(at: swap.installed) }

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        swap.recoverInterruptedSwap()
        status = isInstalled ? .installed(version: installedVersion) : .notInstalled
        switch ModelUpdatePolicy.launchAction(isInstalled: isInstalled, autoCheck: automaticChecks) {
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
        guard work == nil else { return }
        guard isInstalled else { return downloadModel() }
        status = .checking
        work = Task {
            defer { self.work = nil }
            let latest: PublishedModel
            do {
                latest = try await self.fetchLatest()
            } catch {
                self.status = .checkFailed(error as? ModelInstallError ?? .network)
                return
            }
            switch ModelUpdatePolicy.decide(installedVersion: self.installedVersion, isInstalled: true, latest: latest.release, autoDownload: self.automaticDownloads) {
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
                self.offered = nil
                self.status = self.installedVersion.map { .upToDate(version: $0) } ?? .notInstalled
                return
            }
            await self.install(latest, isUpdate: isUpdate)
        }
    }

    private func fetchLatest() async throws -> PublishedModel {
        let installer = self.installer
        return try await Task.detached(priority: .utility) { try await installer.fetchLatest() }.value
    }

    private func install(_ latest: PublishedModel, isUpdate: Bool) async {
        let version = latest.release.version
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
            fail(error, isUpdate: isUpdate)
            return
        }

        if !isDictationIdle() {
            status = .waitingToInstall(version: version)
            while !isDictationIdle() {
                try? await Task.sleep(nanoseconds: UInt64(idlePollInterval * 1_000_000_000))
            }
        }

        do {
            try swap.install(staged)
        } catch {
            fail(error, isUpdate: isUpdate)
            return
        }
        guard await reloadModel() else {
            Self.logger.error("new model failed to load; rolling back")
            try? swap.rollback()
            if isUpdate { _ = await reloadModel() }
            fail(ModelInstallError.installFailed, isUpdate: isUpdate)
            return
        }
        swap.commit()
        ModelStaging(modelsDirectory: installer.modelsDirectory, version: version).removeAll()
        offered = nil
        status = .upToDate(version: version)
        Self.logger.info("installed model \(version, privacy: .public)")
        onInstalled?(!isUpdate)
    }

    private func apply(_ progress: ModelInstallProgress, version: String, isUpdate: Bool) {
        guard stagingVersion == version else { return }
        switch progress {
        case .downloading(let fraction):
            if case .preparing = status { return }
            if case .downloading(_, let current, _) = status, ModelStatus.percent(current) == ModelStatus.percent(fraction) { return }
            status = .downloading(version: version, fraction: fraction, isUpdate: isUpdate)
        case .preparing:
            status = .preparing(version: version, isUpdate: isUpdate)
        }
    }

    private func fail(_ error: Error, isUpdate: Bool) {
        let installError = error as? ModelInstallError ?? .installFailed
        Self.logger.error("model install failed: \(String(describing: installError), privacy: .public)")
        status = .failed(installError, isUpdate: isUpdate)
        onFailure?(isUpdate ? .modelUpdateFailed : .modelDownloadFailed)
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
                self.checkNow()
            }
        }
    }
}
