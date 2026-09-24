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
            if didModelFailToLoad {
                let row = MenuStatusRow.modelLoadFailed.title
                return String(localized: "The model couldn't be loaded. Open the Sorla menu and choose “\(row)”.", bundle: Localization.bundle)
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

    // A push-to-talk press may still become a ⌘-shortcut, so its refusal is only reported on release.
    public static func waitsForRelease(mode: RecordingMode) -> Bool {
        mode == .pushToTalk
    }
}
