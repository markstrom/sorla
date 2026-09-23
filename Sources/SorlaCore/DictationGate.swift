// Without an installed model a transcription can only fail, so dictation is refused with a reason instead.
public enum DictationGate {
    public static func blockedMessage(isModelInstalled: Bool, model: ModelStatus) -> String? {
        guard !isModelInstalled else { return nil }
        switch model {
        case .downloading(_, let fraction, _):
            return "The Swedish model is still downloading (\(ModelStatus.percent(fraction))%). Dictation will work once it's ready."
        case .preparing, .waitingToInstall:
            return "The Swedish model is being prepared. Dictation will work in a moment."
        default:
            return "The Swedish model isn't installed yet. Open the Sorla menu to download it."
        }
    }

    // A push-to-talk press may still become a ⌘-shortcut, so its refusal is only reported on release.
    public static func waitsForRelease(mode: RecordingMode) -> Bool {
        mode == .pushToTalk
    }
}
