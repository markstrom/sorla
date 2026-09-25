import Foundation

// What opening Sorla again while it runs (from Program, Spotlight or `open`) shows. Settings is reachable that way when
// the menu bar icon is hidden behind the notch, but during setup it would bury the window the user needs (#80).
public enum ReopenTarget: Equatable, Sendable {
    case setup
    case settings

    // An open setup window is brought forward; otherwise it opens while onboarding isn't finished or a checklist row
    // still needs the user, the same rows that open it at launch or from the menu.
    public static func onReopen(
        isSetupOpen: Bool,
        hasCompletedOnboarding: Bool,
        microphone: MicrophoneAccess,
        problems: Set<RecoveryProblem>
    ) -> ReopenTarget {
        if isSetupOpen { return .setup }
        if !hasCompletedOnboarding || microphone != .granted { return .setup }
        return problems.contains { $0.surface == .setup } ? .setup : .settings
    }
}
