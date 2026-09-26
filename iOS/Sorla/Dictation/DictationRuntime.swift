import UIKit

// The one dictation session of this process, shared by the app intents and the UI.
@MainActor
final class DictationRuntime: ObservableObject {
    static let shared = DictationRuntime()

    let log: DictationLog
    let coordinator: DictationCoordinator
    // Only the outcome's wording is kept for the UI, never the transcript.
    @Published private(set) var lastMessage: String?

    private var memoryWarningObserver: NSObjectProtocol?

    private init() {
        let log = DictationLog()
        self.log = log
        coordinator = DictationCoordinator(
            recorder: LiveDictationRecorder(),
            transcriber: PhoneTranscriptionEngine(),
            system: LiveDictationSystem(log: log),
            limitWatch: RecordingLimitWatch(limit: Self.recordingLimit)
        )
    }

    // Two minutes for the prototype: long enough for dictation, short enough to bound background compute.
    // The final limit comes from the #65 measurements.
    static let recordingLimit = RecordingLimit(maximum: 120, warningLead: 10)

    func launch() {
        LiveDictationSystem.endStaleActivities()
        ModelStorage.excludeFromBackup()
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.coordinator.unloadModelIfIdle() }
            }
        }
    }

    func toggle(foreground: ForegroundTransition? = nil) async -> DictationOutcome {
        let outcome = await coordinator.toggle(foreground: foreground)
        lastMessage = outcome.message
        return outcome
    }

    func cancel() async {
        if coordinator.cancel() {
            lastMessage = DictationOutcome.cancelled.message
        }
    }
}
