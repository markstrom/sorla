import CoreFoundation
import Foundation

// Names of System Settings items as the running macOS shows them, in the language System Settings is shown in (#74, #79).
public enum SystemSettingsName {
    public enum Item: CaseIterable, Sendable {
        case accessibility
        case microphone
        case sound
        case loginItems
        case keyboard
        case pressGlobeKeyTo
        case doNothing
    }

    public enum Language: Sendable, Equatable {
        case english
        case swedish

        // Sorla only knows the English and Swedish names, so a system in any other language gets the English ones.
        public static func first(in identifiers: [String]) -> Language {
            for identifier in identifiers {
                let code = identifier.lowercased()
                if code == "sv" || code.hasPrefix("sv-") || code.hasPrefix("sv_") { return .swedish }
                if code == "en" || code.hasPrefix("en-") || code.hasPrefix("en_") { return .english }
            }
            return .english
        }

        // The global list, since a language chosen for Sorla alone in Language & Region is kept in Sorla's own domain.
        static var ofSystem: Language {
            let global = CFPreferencesCopyAppValue("AppleLanguages" as CFString, kCFPreferencesAnyApplication) as? [String]
            return first(in: global ?? Locale.preferredLanguages)
        }

        fileprivate func quoted(_ text: String) -> String {
            switch self {
            case .english: return "\"\(text)\""
            case .swedish: return "”\(text)”"
            }
        }
    }

    // Tests pin these; the app reads the running system's.
    @TaskLocal public static var systemMajorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    @TaskLocal public static var systemLanguage = Language.ofSystem

    // Sorla's own language is the one its sentences come from.
    static var uiLanguage: Language {
        Language.first(in: [Localization.bundle.preferredLocalizations.first ?? "en"])
    }

    // What System Settings shows; when Sorla speaks another language, its own name for the item follows in parentheses.
    public static func name(_ item: Item, quoted: Bool = false) -> String {
        let ui = uiLanguage
        let wrap = { (text: String) in quoted ? ui.quoted(text) : text }
        let shown = appleName(item, in: systemLanguage)
        guard systemLanguage != ui else { return wrap(shown) }
        return "\(wrap(shown)) (\(wrap(appleName(item, in: ui))))"
    }

    // Apple's own strings; macOS 27 renamed some, and older versions keep the names Sorla used before.
    public static func appleName(_ item: Item, in language: Language, majorVersion: Int = systemMajorVersion) -> String {
        let is27 = majorVersion >= 27
        switch (item, language) {
        case (.accessibility, .english): return is27 ? "Device Control and Data Access" : "Accessibility"
        case (.accessibility, .swedish): return is27 ? "Enhetskontroll och dataåtkomst" : "Hjälpmedel"
        case (.microphone, .english): return "Microphone"
        case (.microphone, .swedish): return "Mikrofon"
        case (.sound, .english): return "Sound"
        case (.sound, .swedish): return "Ljud"
        case (.loginItems, .english): return "Login Items"
        case (.loginItems, .swedish): return is27 ? "Startobjekt" : "Inloggningsobjekt"
        case (.keyboard, .english): return "Keyboard"
        case (.keyboard, .swedish): return "Tangentbord"
        case (.pressGlobeKeyTo, .english): return "Press 🌐 key to"
        case (.pressGlobeKeyTo, .swedish): return "Tryck på 🌐-tangenten för att"
        case (.doNothing, .english): return "Do Nothing"
        // macOS 27 finishes the "Tryck på 🌐-tangenten för att" sentence with it.
        case (.doNothing, .swedish): return is27 ? "göra ingenting" : "Gör ingenting"
        }
    }
}
