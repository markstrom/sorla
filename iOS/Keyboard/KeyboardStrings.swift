import Foundation

// The keyboard's few strings in Swedish and English, chosen from the person's preferred language.
// Kept in code so the extension carries no string catalogue; the app's localisation is #69.
struct KeyboardStrings {
    let idle: String
    let listening: String
    let captured: String
    let transcribing: String
    let inserted: String
    let fullAccessNeeded: String
    let nextKeyboard: String
    let space: String
    let delete: String
    let returnKey: String

    static let swedish = KeyboardStrings(
        idle: "Tryck på Åtgärdsknappen för att diktera",
        listening: "Lyssnar…",
        captured: "Pausad – tryck på Åtgärdsknappen igen",
        transcribing: "Skriver…",
        inserted: "Infogat",
        fullAccessNeeded: "Slå på Tillåt full åtkomst för Sorla i Inställningar › Allmänt › Tangentbord › Tangentbord › Sorla för att ta emot text från Sorla.",
        nextKeyboard: "Nästa tangentbord",
        space: "mellanslag",
        delete: "Radera",
        returnKey: "retur"
    )

    static let english = KeyboardStrings(
        idle: "Press the Action Button to dictate",
        listening: "Listening…",
        captured: "Paused – press the Action Button again",
        transcribing: "Writing…",
        inserted: "Inserted",
        fullAccessNeeded: "Turn on Allow Full Access for Sorla in Settings › General › Keyboard › Keyboards › Sorla to receive text from Sorla.",
        nextKeyboard: "Next keyboard",
        space: "space",
        delete: "Delete",
        returnKey: "return"
    )

    static var current: KeyboardStrings {
        let language = Locale.preferredLanguages.first ?? "sv"
        return language.hasPrefix("sv") ? swedish : english
    }

    func status(for phase: KeyboardPhase) -> String {
        switch phase {
        case .idle: return idle
        case .listening: return listening
        case .captured: return captured
        case .transcribing: return transcribing
        }
    }
}
