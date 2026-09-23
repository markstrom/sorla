import Foundation

// Without an installed model a transcription can only fail, so dictation is refused with a reason instead.
public enum DictationGate {
    public static func blockedMessage(isModelInstalled: Bool, model: ModelStatus) -> String? {
        guard !isModelInstalled else { return nil }
        switch model {
        case .downloading(_, let fraction, _):
            return String(localized: "The model is still downloading (\(ModelStatus.percent(fraction))%). Dictation will work once it's ready.", bundle: Localization.bundle)
        case .preparing, .waitingToInstall:
            return String(localized: "The model is being prepared (~1 min). Dictation will work once it's ready.", bundle: Localization.bundle)
        default:
            return String(localized: "The model isn't installed yet. Open the Sorla menu to download it.", bundle: Localization.bundle)
        }
    }

    // A push-to-talk press may still become a ⌘-shortcut, so its refusal is only reported on release.
    public static func waitsForRelease(mode: RecordingMode) -> Bool {
        mode == .pushToTalk
    }
}
