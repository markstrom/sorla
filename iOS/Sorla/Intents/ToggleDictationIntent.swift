import AppIntents

// One action for the Action Button or Back Tap: the first run starts listening and returns at once,
// the next stops, transcribes on the phone and returns the result. Sorla itself never writes the
// clipboard here; the Shortcut copies the text only when `Ready to Paste` is true.
// LiveActivityIntent is what lets the app start its Live Activity while in the background (the device refused with .visibility without it).
struct ToggleDictationIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Diktera med Sorla"
    static let description = IntentDescription(
        "Starts dictation the first time and stops it the next. Returns the transcribed text only when there is something to paste."
    )

    // Runs in the background, but may come to the foreground when it decides to. Only a start does: iOS refuses to
    // start audio input from the background (kAUStartIO, 2003329396, on iOS 27), so Sorla opens briefly to start
    // listening. Stopping and transcribing stay in the background.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<DictationResultEntity> {
        let outcome = await DictationRuntime.shared.toggle(foreground: IntentForegroundTransition(intent: self))
        return .result(value: DictationResultEntity(outcome))
    }
}

@MainActor
private struct IntentForegroundTransition: ForegroundTransition {
    let intent: ToggleDictationIntent

    var isRunningInBackground: Bool {
        intent.systemContext.currentMode == .background
    }

    var canContinueInForeground: Bool {
        intent.systemContext.currentMode.canContinueInForeground
    }

    // alwaysConfirm false: no "Continue in Sorla?" question when iOS doesn't insist on one.
    func continueInForeground() async throws {
        try await intent.continueInForeground("Sorla opens to start listening.", alwaysConfirm: false)
    }
}

struct DictationResultEntity: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sorla Dictation Result"

    @Property(title: "Outcome")
    var outcome: DictationOutcomeKind

    @Property(title: "Ready to Paste")
    var readyToPaste: Bool

    @Property(title: "Text")
    var text: String?

    @Property(title: "Message")
    var message: String

    init() {
        outcome = .failed
        readyToPaste = false
        text = nil
        message = ""
    }

    init(_ result: DictationOutcome) {
        self.init()
        outcome = DictationOutcomeKind(result)
        text = result.textToCopy
        readyToPaste = text != nil
        message = result.message
    }

    // Shown in Shortcuts' output preview, so it carries the status wording and never the transcript.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(message)")
    }
}

enum DictationOutcomeKind: String, AppEnum {
    case started
    case transcribed
    case nothingHeard
    case cancelled
    case busy
    case failed

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sorla Dictation Outcome"
    static let caseDisplayRepresentations: [DictationOutcomeKind: DisplayRepresentation] = [
        .started: "Started",
        .transcribed: "Transcribed",
        .nothingHeard: "Nothing Heard",
        .cancelled: "Cancelled",
        .busy: "Busy",
        .failed: "Failed",
    ]

    init(_ outcome: DictationOutcome) {
        switch outcome {
        case .started: self = .started
        case .transcribed(let text): self = text.isEmpty ? .nothingHeard : .transcribed
        case .nothingHeard: self = .nothingHeard
        case .cancelled: self = .cancelled
        case .busy: self = .busy
        case .failed: self = .failed
        }
    }
}

struct SorlaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleDictationIntent(),
            phrases: ["Diktera med \(.applicationName)", "Dictate with \(.applicationName)"],
            shortTitle: "Diktera",
            systemImageName: "mic"
        )
    }
}
