import Foundation

// The app's side of the Sorla keyboard: the dictation phase for its status line, and each successful non-empty
// transcript for it to insert. The Shortcut contract is unchanged (the intent still returns Ready to Paste and Text),
// and the app still never writes the clipboard.
@MainActor
final class KeyboardHandoffPublisher {
    private let store: TranscriptHandoffStore?
    private let diagnose: (String) -> Void
    private var lastPhase: KeyboardPhase?

    init(store: TranscriptHandoffStore?, diagnose: @escaping (String) -> Void) {
        self.store = store
        self.diagnose = diagnose
    }

    // A new process owns no dictation, so whatever phase an earlier one left behind is over.
    func launch() {
        store?.removeExpired()
        send(.idle)
    }

    func publish(_ phase: DictationPhase) {
        send(KeyboardPhase(phase))
    }

    // Only a transcript that the Shortcut would be allowed to paste reaches the keyboard.
    func deliver(_ outcome: DictationOutcome) {
        guard let text = outcome.textToCopy else { return }
        guard let store else {
            diagnose("keyboard: no App Group container, transcript not handed over")
            return
        }
        do {
            try store.offer(text)
        } catch {
            let error = error as NSError
            diagnose("keyboard: hand-over failed (\(error.domain) \(error.code))")
        }
    }

    private func send(_ phase: KeyboardPhase) {
        guard phase != lastPhase else { return }
        lastPhase = phase
        store?.publish(phase)
    }
}

extension KeyboardPhase {
    init(_ phase: DictationPhase) {
        switch phase {
        case .idle: self = .idle
        case .listening: self = .listening
        case .captured: self = .captured
        case .transcribing: self = .transcribing
        }
    }
}
