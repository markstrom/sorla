import Foundation

// SorlaCore has no resources; its wording is translated in the app bundle's Localizable.strings.
public enum Localization {
    @TaskLocal public static var bundle: Bundle = .main

    // Numbers follow the UI language, so a Swedish sentence gets "1,4 GB" and an English one "1.4 GB".
    static var locale: Locale {
        Locale(identifier: bundle.preferredLocalizations.first ?? "en")
    }
}
