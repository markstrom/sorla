import Foundation

// What the menu bar icon says at a glance (#76). The mark follows the model; a badge in the top corner says the user
// has to do something: restart a replaced Sorla (#43), or fix a blocker from the setup window's checklist (#72).
public struct MenuBarIconState: Equatable, Sendable {
    public enum Mark: Equatable, Sendable {
        // The filled dot: the model is loaded.
        case ready
        // A ring and dimmed bars: the model isn't loaded, whether it is on its way, missing or failed; the badge tells which.
        case notReady
    }

    public enum Badge: Equatable, Sendable {
        case attention
        case restart
    }

    public let mark: Mark
    public let badge: Badge?
    public let accessibilityDescription: String

    public init(mark: Mark, badge: Badge?, accessibilityDescription: String) {
        self.mark = mark
        self.badge = badge
        self.accessibilityDescription = accessibilityDescription
    }

    // `problems` is what the setup and recovery windows check (RecoveryProblem.current), so the badge and they agree.
    public static func current(isModelReady: Bool, phase: DictationPhase, problems: Set<RecoveryProblem>) -> MenuBarIconState {
        let mark: Mark = isModelReady ? .ready : .notReady
        // A restart also retries whatever else is wrong, so its badge wins.
        if problems.contains(.restartRequired) {
            return MenuBarIconState(mark: mark, badge: .restart, accessibilityDescription: String(localized: "Sorla (needs a restart)", bundle: Localization.bundle))
        }
        if problems.contains(where: \.badgesTheIcon) {
            return MenuBarIconState(mark: mark, badge: .attention, accessibilityDescription: String(localized: "Sorla (needs attention)", bundle: Localization.bundle))
        }
        guard isModelReady else {
            return MenuBarIconState(mark: mark, badge: nil, accessibilityDescription: String(localized: "Sorla (loading model)", bundle: Localization.bundle))
        }
        switch phase {
        case .recording:
            return MenuBarIconState(mark: mark, badge: nil, accessibilityDescription: String(localized: "Sorla (recording)", bundle: Localization.bundle))
        case .transcribing:
            return MenuBarIconState(mark: mark, badge: nil, accessibilityDescription: String(localized: "Sorla (transcribing)", bundle: Localization.bundle))
        case .idle:
            return MenuBarIconState(mark: mark, badge: nil, accessibilityDescription: "Sorla")
        }
    }
}

extension RecoveryProblem {
    // The setup checklist's blockers. A microphone that failed to start had its own dialog and may be back by now,
    // and a restart has a badge of its own.
    var badgesTheIcon: Bool {
        switch self {
        case .microphoneAccess, .accessibility, .model: return true
        case .microphoneStart, .restartRequired: return false
        }
    }
}
