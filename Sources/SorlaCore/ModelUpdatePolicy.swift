public enum ModelLaunchAction: Equatable, Sendable {
    case none
    case check
    case install
}

public enum ModelUpdateDecision: Equatable, Sendable {
    case none
    case notify(version: String)
    case download(version: String)
}

public enum ModelUpdatePolicy {
    // With a model installed and automatic checks off, launch must not touch the network at all.
    public static func launchAction(isInstalled: Bool, autoCheck: Bool) -> ModelLaunchAction {
        guard isInstalled else { return .install }
        return autoCheck ? .check : .none
    }

    // A version that already failed here is only offered, so it is retried when the user asks rather than every day.
    public static func decide(installedVersion: String?, isInstalled: Bool, latest: ModelRelease, autoDownload: Bool, failedVersion: String? = nil) -> ModelUpdateDecision {
        guard latest.isCompatible, let latestVersion = latest.semanticVersion else { return .none }
        guard isInstalled else { return .download(version: latest.version) }
        if let installed = installedVersion.flatMap(SemanticVersion.init), installed >= latestVersion {
            return .none
        }
        let failedBefore = failedVersion.flatMap(SemanticVersion.init) == latestVersion
        return autoDownload && !failedBefore ? .download(version: latest.version) : .notify(version: latest.version)
    }
}
