// Tells VoiceOver how a dictation went, holding anything said while the microphone is open until it closes.
@MainActor
public final class DictationAnnouncer {
    private var gate = AnnouncementGate()
    private let controller: RecordingController
    private let post: (String) -> Void

    // Takes over the controller's paste and microphone-closed callbacks.
    public init(controller: RecordingController, isVoiceOverEnabled: @escaping () -> Bool, post: @escaping (String) -> Void) {
        self.controller = controller
        self.post = post
        controller.onPaste = { [weak self] in
            // Only that ⌘V was sent: that doesn't prove the text landed.
            guard isVoiceOverEnabled() else { return }
            self?.announce(String(localized: "Pasting text", bundle: Localization.bundle))
        }
        controller.onMicrophoneClosed = { [weak self] in
            self?.microphoneClosed()
        }
    }

    public func announce(_ text: String) {
        guard let text = gate.request(text, isMicrophoneOpen: controller.isMicrophoneOpen) else { return }
        post(text)
    }

    private func microphoneClosed() {
        guard let text = gate.microphoneClosed() else { return }
        post(text)
    }
}
