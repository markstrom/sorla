import AppIntents

// The Live Activity's cancel button. A LiveActivityIntent runs in the app's process, so the
// extension only needs the type to build the button; it never performs it.
struct CancelDictationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Cancel Sorla Dictation"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        #if SORLA_APP
        await DictationRuntime.shared.cancel()
        #endif
        return .result()
    }
}
