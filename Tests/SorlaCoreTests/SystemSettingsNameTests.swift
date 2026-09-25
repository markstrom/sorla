import XCTest
@testable import SorlaCore

// #74, #79: System Settings items are named as the running macOS shows them, in the language System Settings uses,
// with Sorla's own name for them in parentheses when Sorla speaks another language.
final class SystemSettingsNameTests: XCTestCase {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources")

    private var bundleDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in bundleDirectories {
            try FileManager.default.removeItem(at: directory)
        }
    }

    // A bundle holding one .lproj, so that language is Sorla's regardless of the Mac's languages.
    private func languageBundle(_ language: String) throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SorlaSystemSettingsNameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("\(language).lproj"),
            withDestinationURL: Self.resources.appendingPathComponent("\(language).lproj")
        )
        bundleDirectories.append(directory)
        return try XCTUnwrap(Bundle(url: directory))
    }

    // Sorla's language, the language System Settings is shown in, and the macOS major version.
    private func with<T>(ui: String, system: SystemSettingsName.Language, macOS: Int, _ body: () throws -> T) throws -> T {
        try Localization.$bundle.withValue(languageBundle(ui)) {
            try SystemSettingsName.$systemLanguage.withValue(system) {
                try SystemSettingsName.$systemMajorVersion.withValue(macOS, operation: body)
            }
        }
    }

    func testMacOS14To26KeepTheOldNames() {
        for version in [14, 26] {
            XCTAssertEqual(SystemSettingsName.appleName(.accessibility, in: .english, majorVersion: version), "Accessibility")
            XCTAssertEqual(SystemSettingsName.appleName(.accessibility, in: .swedish, majorVersion: version), "Hjälpmedel")
            XCTAssertEqual(SystemSettingsName.appleName(.loginItems, in: .english, majorVersion: version), "Login Items")
            XCTAssertEqual(SystemSettingsName.appleName(.loginItems, in: .swedish, majorVersion: version), "Inloggningsobjekt")
            XCTAssertEqual(SystemSettingsName.appleName(.doNothing, in: .swedish, majorVersion: version), "Gör ingenting")
        }
    }

    // Checked against System Settings' own strings on macOS 27.0 (26A428).
    func testMacOS27UsesItsNewNames() {
        for version in [27, 28] {
            XCTAssertEqual(SystemSettingsName.appleName(.accessibility, in: .english, majorVersion: version), "Device Control and Data Access")
            XCTAssertEqual(SystemSettingsName.appleName(.accessibility, in: .swedish, majorVersion: version), "Enhetskontroll och dataåtkomst")
            XCTAssertEqual(SystemSettingsName.appleName(.loginItems, in: .english, majorVersion: version), "Login Items")
            XCTAssertEqual(SystemSettingsName.appleName(.loginItems, in: .swedish, majorVersion: version), "Startobjekt")
            XCTAssertEqual(SystemSettingsName.appleName(.doNothing, in: .swedish, majorVersion: version), "göra ingenting")
        }
    }

    func testTheOtherNamesAreTheSameOnEveryVersion() {
        for version in [14, 26, 27] {
            let names = { (language: SystemSettingsName.Language) in
                [SystemSettingsName.Item.microphone, .sound, .keyboard, .pressGlobeKeyTo].map {
                    SystemSettingsName.appleName($0, in: language, majorVersion: version)
                }
            }
            XCTAssertEqual(names(.english), ["Microphone", "Sound", "Keyboard", "Press 🌐 key to"])
            XCTAssertEqual(names(.swedish), ["Mikrofon", "Ljud", "Tangentbord", "Tryck på 🌐-tangenten för att"])
        }
    }

    // System Settings is in the first preferred language it has; Sorla only knows the English and Swedish names.
    func testTheSystemLanguageIsTheFirstSwedishOrEnglishOne() {
        XCTAssertEqual(SystemSettingsName.Language.first(in: ["sv-SE", "en-US"]), .swedish)
        XCTAssertEqual(SystemSettingsName.Language.first(in: ["sv"]), .swedish)
        XCTAssertEqual(SystemSettingsName.Language.first(in: ["en-GB", "sv-SE"]), .english)
        XCTAssertEqual(SystemSettingsName.Language.first(in: ["de-DE", "sv-SE"]), .swedish)
        XCTAssertEqual(SystemSettingsName.Language.first(in: ["fr-FR"]), .english)
        XCTAssertEqual(SystemSettingsName.Language.first(in: []), .english)
    }

    func testTheSameLanguageGivesOneName() throws {
        try with(ui: "en", system: .english, macOS: 27) {
            XCTAssertEqual(SystemSettingsName.name(.accessibility), "Device Control and Data Access")
            XCTAssertEqual(SystemSettingsName.name(.doNothing, quoted: true), "\"Do Nothing\"")
        }
        try with(ui: "sv", system: .swedish, macOS: 27) {
            XCTAssertEqual(SystemSettingsName.name(.accessibility), "Enhetskontroll och dataåtkomst")
            XCTAssertEqual(SystemSettingsName.name(.doNothing, quoted: true), "”göra ingenting”")
        }
        try with(ui: "sv", system: .swedish, macOS: 26) {
            XCTAssertEqual(SystemSettingsName.name(.loginItems), "Inloggningsobjekt")
        }
    }

    func testEnglishSorlaOnASwedishMacNamesTheSwedishItemFirst() throws {
        try with(ui: "en", system: .swedish, macOS: 27) {
            XCTAssertEqual(SystemSettingsName.name(.accessibility), "Enhetskontroll och dataåtkomst (Device Control and Data Access)")
            XCTAssertEqual(SystemSettingsName.name(.loginItems), "Startobjekt (Login Items)")
            XCTAssertEqual(SystemSettingsName.name(.doNothing, quoted: true), "\"göra ingenting\" (\"Do Nothing\")")
        }
        try with(ui: "en", system: .swedish, macOS: 26) {
            XCTAssertEqual(SystemSettingsName.name(.accessibility), "Hjälpmedel (Accessibility)")
            XCTAssertEqual(SystemSettingsName.name(.loginItems), "Inloggningsobjekt (Login Items)")
        }
    }

    func testSwedishSorlaOnAnEnglishMacNamesTheEnglishItemFirst() throws {
        try with(ui: "sv", system: .english, macOS: 27) {
            XCTAssertEqual(SystemSettingsName.name(.accessibility), "Device Control and Data Access (Enhetskontroll och dataåtkomst)")
            XCTAssertEqual(SystemSettingsName.name(.loginItems), "Login Items (Startobjekt)")
            XCTAssertEqual(SystemSettingsName.name(.pressGlobeKeyTo, quoted: true), "”Press 🌐 key to” (”Tryck på 🌐-tangenten för att”)")
        }
        try with(ui: "sv", system: .english, macOS: 26) {
            XCTAssertEqual(SystemSettingsName.name(.loginItems), "Login Items (Inloggningsobjekt)")
        }
    }

    // The paste permission's explanation in the setup window, and its button's name for VoiceOver and Voice Control.
    func testThePastePermissionRowInEachLanguageCombination() throws {
        let row = { (WelcomeRow.accessibility.purpose, WelcomeChecklist.buttonName(WelcomeChecklist.accessibilityRow(isTrusted: false))) }
        try with(ui: "en", system: .english, macOS: 27) {
            XCTAssertEqual(row().0, "So Sorla can paste where you type. In System Settings the permission is called Device Control and Data Access.")
            XCTAssertEqual(row().1, "Open Device Control and Data Access in System Settings")
        }
        try with(ui: "sv", system: .swedish, macOS: 27) {
            XCTAssertEqual(row().0, "Så att Sorla kan klistra in där du skriver. I Systeminställningar heter behörigheten Enhetskontroll och dataåtkomst.")
            XCTAssertEqual(row().1, "Öppna Enhetskontroll och dataåtkomst i Systeminställningar")
        }
        try with(ui: "en", system: .swedish, macOS: 27) {
            XCTAssertEqual(row().0, "So Sorla can paste where you type. In System Settings the permission is called Enhetskontroll och dataåtkomst (Device Control and Data Access).")
            XCTAssertEqual(row().1, "Open Enhetskontroll och dataåtkomst (Device Control and Data Access) in System Settings")
        }
        try with(ui: "sv", system: .english, macOS: 27) {
            XCTAssertEqual(row().0, "Så att Sorla kan klistra in där du skriver. I Systeminställningar heter behörigheten Device Control and Data Access (Enhetskontroll och dataåtkomst).")
            XCTAssertEqual(row().1, "Öppna Device Control and Data Access (Enhetskontroll och dataåtkomst) i Systeminställningar")
        }
        try with(ui: "en", system: .swedish, macOS: 26) {
            XCTAssertEqual(row().0, "So Sorla can paste where you type. In System Settings the permission is called Hjälpmedel (Accessibility).")
        }
    }

    func testTheLoginItemsHintInEachLanguageCombination() throws {
        let hint = { (SettingsRow.loginItemApprovalHint, SettingsRow.openLoginItemsSettings) }
        try with(ui: "en", system: .english, macOS: 27) {
            XCTAssertEqual(hint().0, "Sorla needs approval in Login Items to launch at login.")
            XCTAssertEqual(hint().1, "Open Login Items Settings…")
        }
        try with(ui: "sv", system: .swedish, macOS: 27) {
            XCTAssertEqual(hint().0, "Sorla behöver godkännas under Startobjekt för att starta vid inloggning.")
            XCTAssertEqual(hint().1, "Öppna inställningar för Startobjekt…")
        }
        try with(ui: "sv", system: .swedish, macOS: 26) {
            XCTAssertEqual(hint().0, "Sorla behöver godkännas under Inloggningsobjekt för att starta vid inloggning.")
            XCTAssertEqual(hint().1, "Öppna inställningar för Inloggningsobjekt…")
        }
        try with(ui: "en", system: .swedish, macOS: 27) {
            XCTAssertEqual(hint().0, "Sorla needs approval in Startobjekt (Login Items) to launch at login.")
            XCTAssertEqual(hint().1, "Open Startobjekt (Login Items) Settings…")
        }
        try with(ui: "sv", system: .english, macOS: 27) {
            XCTAssertEqual(hint().0, "Sorla behöver godkännas under Login Items (Startobjekt) för att starta vid inloggning.")
            XCTAssertEqual(hint().1, "Öppna inställningar för Login Items (Startobjekt)…")
        }
    }

    func testTheFnKeyHintInEachLanguageCombination() throws {
        try with(ui: "en", system: .english, macOS: 27) {
            XCTAssertEqual(
                SettingsRow.fnKeyHint,
                "Pressing 🌐/Fn alone may also change the input source, show emoji or start dictation, depending on the system's \"Press 🌐 key to\" setting. Set it to \"Do Nothing\" in Keyboard settings."
            )
            XCTAssertEqual(SettingsRow.openKeyboardSettings, "Open Keyboard Settings…")
        }
        try with(ui: "sv", system: .swedish, macOS: 27) {
            XCTAssertEqual(
                SettingsRow.fnKeyHint,
                "Ett tryck på bara 🌐/Fn kan också byta inmatningskälla, visa emojier eller starta diktering, beroende på systemets inställning ”Tryck på 🌐-tangenten för att”. Ställ in den på ”göra ingenting” i inställningarna för Tangentbord."
            )
            XCTAssertEqual(SettingsRow.openKeyboardSettings, "Öppna inställningar för Tangentbord…")
        }
        try with(ui: "sv", system: .swedish, macOS: 26) {
            XCTAssertTrue(SettingsRow.fnKeyHint.hasSuffix("Ställ in den på ”Gör ingenting” i inställningarna för Tangentbord."))
        }
        try with(ui: "en", system: .swedish, macOS: 27) {
            XCTAssertEqual(
                SettingsRow.fnKeyHint,
                "Pressing 🌐/Fn alone may also change the input source, show emoji or start dictation, depending on the system's \"Tryck på 🌐-tangenten för att\" (\"Press 🌐 key to\") setting. Set it to \"göra ingenting\" (\"Do Nothing\") in Tangentbord (Keyboard) settings."
            )
            XCTAssertEqual(SettingsRow.openKeyboardSettings, "Open Tangentbord (Keyboard) Settings…")
        }
    }

    // The tab's name changed in Swedish on macOS 27, so Sorla names only the Sound pane and says what to check there.
    func testTheSoundInputIsNamedTheSameOnEveryVersion() throws {
        for version in [26, 27] {
            try with(ui: "en", system: .english, macOS: version) {
                XCTAssertEqual(SorlaIssue.noInputDevice.menuTitle, "No microphone found — check the sound input in Sound settings")
                XCTAssertEqual(RecoveryDialog.microphoneStart.actionTitle, "Open Sound Settings")
            }
            try with(ui: "sv", system: .swedish, macOS: version) {
                XCTAssertEqual(SorlaIssue.noInputDevice.menuTitle, "Ingen mikrofon hittades – kontrollera ljudingången i inställningarna för Ljud")
                XCTAssertEqual(
                    RecoveryDialog.microphoneStart.message,
                    "Sorla behöver en mikrofon som är ansluten och vald som ljudingång. Kontrollera ljudingången i inställningarna för Ljud och försök sedan igen."
                )
            }
        }
        try with(ui: "en", system: .swedish, macOS: 27) {
            XCTAssertEqual(SorlaIssue.microphoneMuted.menuTitle, "Microphone seems to be muted — check the sound input in Ljud (Sound) settings")
        }
        try with(ui: "sv", system: .english, macOS: 27) {
            XCTAssertEqual(RecoveryDialog.microphoneStart.actionTitle, "Öppna inställningar för Sound (Ljud)")
        }
    }

    func testTheMenuRowAndMicrophoneButtonFollowTheSystemLanguage() throws {
        try with(ui: "en", system: .swedish, macOS: 27) {
            XCTAssertEqual(SorlaIssue.accessibilityAccessNeeded.menuTitle, "Enhetskontroll och dataåtkomst (Device Control and Data Access) permission needed to paste")
            XCTAssertEqual(WelcomeChecklist.buttonName(WelcomeChecklist.microphoneRow(.denied)), "Open Mikrofon (Microphone) in System Settings")
        }
        try with(ui: "sv", system: .english, macOS: 27) {
            XCTAssertEqual(SorlaIssue.accessibilityAccessNeeded.menuTitle, "Behörigheten Device Control and Data Access (Enhetskontroll och dataåtkomst) behövs för att klistra in")
            XCTAssertEqual(WelcomeChecklist.buttonName(WelcomeChecklist.microphoneRow(.denied)), "Öppna Microphone (Mikrofon) i Systeminställningar")
        }
    }

    // The deep link still opens the pane on macOS 27, so it stays the same for every version.
    func testTheSettingsLinkIsTheSameOnEveryVersion() {
        for version in [14, 26, 27] {
            SystemSettingsName.$systemMajorVersion.withValue(version) {
                XCTAssertEqual(
                    SorlaIssue.accessibilityAccessNeeded.settingsURL,
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                )
            }
        }
    }
}
