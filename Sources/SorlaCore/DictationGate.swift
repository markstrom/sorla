import Foundation

// Without a loaded model a recording can't be transcribed in time, so dictation is refused with a reason instead.
public enum DictationGate {
    public static func blockedMessage(
        isModelInstalled: Bool,
        isModelLoading: Bool = false,
        didModelFailToLoad: Bool = false,
        model: ModelStatus
    ) -> String? {
        if isModelInstalled {
            if isModelLoading {
                return String(localized: "The model is loading (~1 min). Dictation will work once it's ready.", bundle: Localization.bundle)
            }
            // The menu's row opens the setup window, where Try Again is (#76).
            if didModelFailToLoad {
                return String(localized: "The model couldn't be loaded. Open the Sorla menu to try again.", bundle: Localization.bundle)
            }
            return nil
        }
        switch model {
        case .downloading(_, let fraction, _):
            return String(localized: "The model is still downloading (\(ModelStatus.percent(fraction))%). Dictation will work once it's ready.", bundle: Localization.bundle)
        case .preparing, .waitingToInstall:
            return String(localized: "The model is being prepared (~1 min). Dictation will work once it's ready.", bundle: Localization.bundle)
        default:
            return String(localized: "The model isn't installed yet. Open the Sorla menu to download it.", bundle: Localization.bundle)
        }
    }

    // A model on its way shows an hourglass; one that needs the user's help shows a warning.
    public static func refusal(
        isModelInstalled: Bool,
        isModelLoading: Bool = false,
        didModelFailToLoad: Bool = false,
        model: ModelStatus
    ) -> DictationCue? {
        guard let message = blockedMessage(
            isModelInstalled: isModelInstalled,
            isModelLoading: isModelLoading,
            didModelFailToLoad: didModelFailToLoad,
            model: model
        ) else { return nil }
        if isModelInstalled {
            return isModelLoading ? .waitingForModel(message) : .failed(message)
        }
        switch model {
        case .downloading, .preparing, .waitingToInstall:
            return .waitingForModel(message)
        default:
            return .failed(message)
        }
    }

    // Only a model that needs the user's help is a problem worth a window; one on its way just gets the hourglass.
    public static func modelProblem(
        isModelInstalled: Bool,
        isModelLoading: Bool = false,
        didModelFailToLoad: Bool = false,
        model: ModelStatus
    ) -> ModelProblem? {
        if isModelInstalled {
            return !isModelLoading && didModelFailToLoad ? .loadFailed : nil
        }
        switch model {
        case .downloading, .preparing, .waitingToInstall: return nil
        case .failed(.insufficientDiskSpace, _): return .insufficientDiskSpace
        case .failed: return .downloadFailed
        default: return .missing
        }
    }

    public static func modelRefusal(
        isModelInstalled: Bool,
        isModelLoading: Bool = false,
        didModelFailToLoad: Bool = false,
        model: ModelStatus
    ) -> DictationRefusal? {
        guard let cue = refusal(isModelInstalled: isModelInstalled, isModelLoading: isModelLoading, didModelFailToLoad: didModelFailToLoad, model: model) else { return nil }
        let problem = modelProblem(isModelInstalled: isModelInstalled, isModelLoading: isModelLoading, didModelFailToLoad: didModelFailToLoad, model: model)
        return DictationRefusal(cue: cue, problem: problem.map(RecoveryProblem.model))
    }

    // A replaced Sorla's pastes are dropped (#7), so a press isn't recorded; the user chooses when to restart (#72).
    // One that can't reopen itself records as before and leaves the text on the clipboard.
    public static func restartRefusal(isAppReplaced: Bool, canRestart: Bool) -> DictationRefusal? {
        isAppReplaced && canRestart ? DictationRefusal(cue: .restartNeeded, problem: .restartRequired) : nil
    }

    // A push-to-talk press may still become a ⌘-shortcut, so its refusal is only reported on release.
    public static func waitsForRelease(mode: RecordingMode) -> Bool {
        mode == .pushToTalk
    }
}
