import XCTest
@testable import SorlaCore

final class LocalizationTests: XCTestCase {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources")

    private func strings(_ language: String, table: String = "Localizable") throws -> [String: String] {
        let url = Self.resources.appendingPathComponent("\(language).lproj/\(table).strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String], "\(url.path) is not a strings table")
    }

    private func placeholders(_ text: String) throws -> [String] {
        let withoutPercentSigns = text.replacingOccurrences(of: "%%", with: "")
        let pattern = try Regex(#"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA]"#)
        return withoutPercentSigns.matches(of: pattern).map { String(withoutPercentSigns[$0.range]) }
    }

    private var languageBundleDirectories: [URL] = []

    // A bundle holding one .lproj, so that language is its preferred localization regardless of the Mac's languages.
    private func languageBundle(_ language: String) throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SorlaLocalizationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("\(language).lproj"),
            withDestinationURL: Self.resources.appendingPathComponent("\(language).lproj")
        )
        languageBundleDirectories.append(directory)
        return try XCTUnwrap(Bundle(url: directory))
    }

    private var swedish: Bundle {
        get throws { try languageBundle("sv") }
    }

    override func tearDownWithError() throws {
        for directory in languageBundleDirectories {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testEveryKeyIsTranslatedInBothLanguages() throws {
        for table in ["Localizable", "InfoPlist"] {
            let english = try strings("en", table: table)
            let swedish = try strings("sv", table: table)
            XCTAssertFalse(english.isEmpty)
            XCTAssertEqual(Set(english.keys).subtracting(swedish.keys), [], "\(table): missing in Swedish")
            XCTAssertEqual(Set(swedish.keys).subtracting(english.keys), [], "\(table): missing in English")
        }
    }

    func testFormatPlaceholdersMatchBetweenLanguages() throws {
        let english = try strings("en")
        let swedish = try strings("sv")
        for (key, englishText) in english {
            XCTAssertEqual(try placeholders(englishText), try placeholders(key), "English: \(key)")
            if let swedishText = swedish[key] {
                XCTAssertEqual(try placeholders(swedishText), try placeholders(key), "Swedish: \(key)")
            }
        }
    }

    // The recording indicator is "indikator" in Swedish; Apple's feature stays "Dynamic Island".
    func testSwedishNeverCallsTheIndicatorAnIsland() throws {
        for text in try strings("sv").values {
            let words = text.lowercased().split { !$0.isLetter }
            XCTAssertFalse(words.contains("ö") || words.contains("ön"), text)
        }
    }

    func testSwedishKeyNamesAndTriggerHints() throws {
        try Localization.$bundle.withValue(swedish) {
            XCTAssertEqual(TriggerKey.rightCommand.displayName, "Höger ⌘")
            XCTAssertEqual(TriggerKey.rightOption.displayName, "Höger ⌥")
            XCTAssertEqual(TriggerKey.rightControl.displayName, "Höger ⌃")
            XCTAssertEqual(TriggerKey.fn.displayName, "Fn")
            XCTAssertEqual(
                TriggerHint.menuTitle(trigger: .rightCommand, mode: .pushToTalk, customShortcut: nil),
                "Starta diktering (håll Höger ⌘)"
            )
            XCTAssertEqual(
                TriggerHint.menuTitle(trigger: .customShortcut, mode: .toggle, customShortcut: "⌃⌥Space"),
                "Starta diktering (tryck på ⌃⌥Space)"
            )
            XCTAssertEqual(
                TriggerHint.menuTitle(trigger: .rightCommand, mode: .pushToTalk, customShortcut: nil, isRecording: true),
                "Stoppa diktering"
            )
        }
    }

    func testSwedishModelStatusRows() throws {
        func title(_ model: ModelStatus) -> String? {
            MenuStatusRow.current(microphoneDenied: false, accessibilityMissing: false, model: model, modelLoadFailed: false)?.title
        }
        try Localization.$bundle.withValue(swedish) {
            XCTAssertEqual(title(.downloading(version: "1", fraction: 0.42, isUpdate: false)), "Laddar ner modellen… 42 %")
            XCTAssertEqual(title(.preparing(version: "1", isUpdate: false)), "Förbereder modellen… ~1 min")
            XCTAssertEqual(title(.notInstalled), "Modellen är inte installerad – Ladda ner")
            XCTAssertEqual(title(.failed(.network, isUpdate: false)), "Nedladdningen av modellen misslyckades – Försök igen")
            XCTAssertEqual(ModelStatus.downloading(version: "1", fraction: 0.42, isUpdate: false).settingsText, "Laddar ner 42 %")
        }
    }

    func testSwedishWelcomeRows() throws {
        try Localization.$bundle.withValue(swedish) {
            XCTAssertEqual(WelcomeChecklist.microphoneRow(.notDetermined), .needsAction(.requestMicrophone, buttonTitle: "Tillåt", note: nil))
            XCTAssertEqual(
                WelcomeChecklist.accessibilityRow(isTrusted: false),
                .needsAction(.openAccessibilitySettings, buttonTitle: "Öppna Systeminställningar", note: nil)
            )
            XCTAssertEqual(
                WelcomeChecklist.modelRow(isInstalled: false, isLoaded: false, loadFailed: false, model: .downloading(version: "1", fraction: 0.34, isUpdate: false)),
                .inProgress("Laddar ner modellen… 34 %")
            )
            XCTAssertEqual(
                WelcomeChecklist.modelRow(isInstalled: false, isLoaded: false, loadFailed: false, model: .notInstalled),
                .needsAction(.downloadModel, buttonTitle: "Ladda ner", note: "Inte installerad")
            )
            XCTAssertEqual(
                WelcomeChecklist.readinessLine(isReady: true, trigger: .rightCommand, mode: .pushToTalk, customShortcut: nil),
                "Sorla är redo. Håll Höger ⌘ för att diktera."
            )
            XCTAssertEqual(WelcomeChecklist.buttonName(WelcomeChecklist.microphoneRow(.notDetermined)), "Tillåt mikrofonåtkomst")
            XCTAssertEqual(WelcomeChecklist.buttonName(WelcomeChecklist.microphoneRow(.denied)), "Öppna Mikrofon i Systeminställningar")
            XCTAssertEqual(WelcomeChecklist.buttonName(WelcomeChecklist.accessibilityRow(isTrusted: false)), "Öppna Hjälpmedel i Systeminställningar")
            XCTAssertEqual(
                WelcomeChecklist.buttonName(WelcomeChecklist.modelRow(isInstalled: false, isLoaded: false, loadFailed: false, model: .failed(.network, isUpdate: false))),
                "Försök ladda ner modellen igen"
            )
            XCTAssertEqual(
                WelcomeChecklist.buttonName(WelcomeChecklist.modelRow(isInstalled: true, isLoaded: false, loadFailed: true, model: .installed(version: "1"))),
                "Försök läsa in modellen igen"
            )
        }
    }

    // #72, #73: the recovery windows and the Welcome window's update note.
    func testSwedishRecoveryWindows() throws {
        try Localization.$bundle.withValue(swedish) {
            XCTAssertEqual(RecoveryDialog.microphoneStart.title, "Sorla kunde inte starta mikrofonen")
            XCTAssertEqual(RecoveryDialog.microphoneStart.actionTitle, "Öppna inställningar för Ljud")
            XCTAssertEqual(RecoveryDialog.notNow, "Inte nu")
            XCTAssertEqual(
                RecoveryDialog.restart(canRestart: true, isTextOnClipboard: true).message,
                "Sorla uppdaterades medan den var igång, och macOS tar inte emot inklistringar från den gamla kopian. Texten ligger i urklippet – stäng fönstret och tryck ⌘V där du skrev. När Sorla startar om öppnas den nya versionen."
            )
            XCTAssertEqual(RecoveryDialog.restart(canRestart: true, isTextOnClipboard: false).actionTitle, "Starta om Sorla")
            XCTAssertEqual(RecoveryDialog.restart(canRestart: false, isTextOnClipboard: false).actionTitle, "Avsluta Sorla")
            XCTAssertEqual(
                WelcomeChecklist.pasteBlockedMessage(isTextOnClipboard: true, isAccessibilityTrusted: false),
                "Texten är klar, men Sorla behöver behörigheten Hjälpmedel för att klistra in den. Texten ligger i urklippet – stäng fönstret och tryck ⌘V där du skrev."
            )
            XCTAssertEqual(WelcomeChecklist.readinessLine(isReady: false, trigger: .rightCommand, mode: .pushToTalk, customShortcut: nil), "Åtgärda punkterna ovan för att prova diktering.")
            XCTAssertEqual(WelcomeChecklist.closeButtonTitle(isReady: false), "Inte nu")
            XCTAssertEqual(WelcomeChecklist.closeButtonTitle(isReady: true), "Klar")
            XCTAssertEqual(
                WelcomeChecklist.modelRow(isInstalled: false, isLoaded: false, loadFailed: false, model: .failed(.insufficientDiskSpace(required: 1_376_514_942), isUpdate: false)),
                .needsAction(.downloadModel, buttonTitle: "Försök igen", note: "Inte tillräckligt med ledigt utrymme (1,4 GB behövs).")
            )
            XCTAssertEqual(
                WelcomeChecklist.updatesNote(autoCheck: false, autoInstall: false),
                "Automatisk sökning efter och installation av uppdateringar är avstängda. Du kan slå på dem i Inställningar."
            )
            XCTAssertEqual(WelcomeChecklist.updatesNote(autoCheck: false, autoInstall: true), "Automatisk sökning efter uppdateringar är avstängd, så inget installeras automatiskt förrän du slår på den i Inställningar.")
            XCTAssertEqual(WelcomeChecklist.updatesNote(autoCheck: true, autoInstall: false), "Sorla söker efter uppdateringar automatiskt men installerar dem inte. Du kan ändra det i Inställningar.")
            XCTAssertEqual(WelcomeChecklist.updateSettingsButtonTitle, "Inställningar för uppdateringar")
            XCTAssertEqual(WelcomeChecklist.updateSettingsButtonName, "Öppna Uppdateringar i Inställningar")
        }
        XCTAssertEqual(try strings("sv")["Set Up Sorla"], "Ställ in Sorla")
    }

    func testSwedishFailedLoadRefusalNamesTheMenuRow() throws {
        try Localization.$bundle.withValue(swedish) {
            XCTAssertEqual(
                DictationGate.blockedMessage(isModelInstalled: true, didModelFailToLoad: true, model: .installed(version: "1")),
                "Modellen kunde inte läsas in. Öppna Sorla-menyn och välj ”Modellen kunde inte läsas in – Försök igen”."
            )
        }
    }

    func testSwedishDictationCues() throws {
        try Localization.$bundle.withValue(swedish) {
            XCTAssertEqual(DictationCue.nothingHeard.announcement(pasteShortcut: nil), "Inget hördes")
            XCTAssertEqual(DictationCue.noText.announcement(pasteShortcut: nil), "Ingen text")
            XCTAssertEqual(DictationCue.microphoneMuted.announcement(pasteShortcut: nil), "Mikrofonen verkar vara avstängd")
            XCTAssertEqual(DictationCue.textOnClipboard.announcement(pasteShortcut: "⌃⌥V"), "Texten ligger i urklippet – tryck ⌃⌥V")
            XCTAssertEqual(DictationCue.releaseKeys.announcement(pasteShortcut: "⌃⌥V"), "Släpp tangenterna och tryck ⌃⌥V igen")
            XCTAssertEqual(DictationCue.releaseKeys.announcement(pasteShortcut: nil), "Släpp tangenterna och försök igen")
            XCTAssertEqual(SorlaIssue.microphoneMuted.menuTitle, "Mikrofonen verkar vara avstängd – kontrollera Ljud › Ingång")
            XCTAssertEqual(SorlaIssue.textOnClipboard(pasteShortcut: "⌃⌥V").menuTitle, "Texten ligger i urklippet – tryck ⌃⌥V")
            XCTAssertEqual(DictationCue(issue: .noInputDevice)?.announcement(pasteShortcut: nil), "Ingen mikrofon hittades")
            XCTAssertEqual(DictationCue.cancelled.announcement(pasteShortcut: nil), "Inspelningen avbröts")
            XCTAssertEqual(DictationCue.nothingToPaste.announcement(pasteShortcut: nil), "Inget att klistra in")
            XCTAssertEqual(RecordingLimit.stopAnnouncement, "Inspelningen stoppades vid gränsen på fem minuter")
            XCTAssertEqual(DictationCue.restartNeeded.announcement(pasteShortcut: nil), "Sorla har uppdaterats och behöver startas om")
            XCTAssertEqual(
                DictationCue.textOnClipboardUntilRestart.announcement(pasteShortcut: nil),
                "Texten ligger i urklippet – tryck ⌘V. Starta om Sorla för att klistra in igen"
            )
            XCTAssertEqual(
                MenuStatusRow.current(microphoneDenied: false, accessibilityMissing: false, model: .upToDate(version: "1"), modelLoadFailed: false, appReplaced: true)?.title,
                "Sorla har uppdaterats – Starta om"
            )
            XCTAssertEqual(
                MenuStatusRow.current(microphoneDenied: false, accessibilityMissing: false, model: .upToDate(version: "1"), modelLoadFailed: false, appReplaced: true, canRestart: false)?.title,
                "Sorla har uppdaterats – Avsluta och öppna den från Program"
            )
            XCTAssertEqual(
                WelcomeChecklist.toggleModeTip(mode: .pushToTalk),
                "Svårt att hålla ner en tangent? Välj Av/på under Läge i Inställningar: tryck en gång för att starta och en gång till för att stoppa."
            )
        }
    }

    func testSwedishUpdates() throws {
        try Localization.$bundle.withValue(swedish) {
            XCTAssertEqual(UpdateRow.app(.upToDate).text, "Senaste")
            XCTAssertEqual(UpdateRow.model(.updateAvailable(version: "1.1.0")).text, "1.1.0 finns")
            XCTAssertEqual(UpdateRow.app(.checking).text, "Söker…")
            XCTAssertEqual(
                MenuStatusRow.current(microphoneDenied: false, accessibilityMissing: false, model: .upToDate(version: "1"), modelLoadFailed: false, appUpdate: .download(version: "1.2.0"))?.title,
                "Sorla 1.2.0 finns – Ladda ner"
            )
        }
        try Localization.$bundle.withValue(swedish) {
            let menu = { (offer: AppUpdateOffer) in
                MenuStatusRow.current(microphoneDenied: false, accessibilityMissing: false, model: .upToDate(version: "1"), modelLoadFailed: false, appUpdate: offer)?.title
            }
            XCTAssertEqual(menu(.install(version: "1.2.0")), "Sorla 1.2.0 finns – Installera och starta om")
            XCTAssertEqual(menu(.homebrew(version: "1.2.0")), "Sorla 1.2.0 finns – Uppdatera med Homebrew")
            XCTAssertEqual(menu(.installing(version: "1.2.0")), "Installerar Sorla 1.2.0…")
            XCTAssertEqual(menu(.failed(version: "1.2.0", .download)), "Kunde inte installera Sorla 1.2.0 – Ladda ner")
            XCTAssertEqual(TransientMenuStatus(updatedTo: "1.2.0", at: Date()).row.title, "Sorla uppdaterades till 1.2.0")
            XCTAssertEqual(UpdateRow.app(.available(version: "1.2.0"), offer: .homebrew(version: "1.2.0")).note, "Uppdatera med Homebrew: brew upgrade --cask sorla")
            XCTAssertEqual(UpdateRow.app(.available(version: "1.2.0"), offer: .installing(version: "1.2.0")).text, "Installerar…")
            XCTAssertEqual(AppInstallFailure.verification.message, "Uppdateringen kunde inte kontrolleras, så Sorla har inte ändrats. Ladda ner den från GitHub i stället.")
            XCTAssertEqual(
                AppUpdateOffer.make(status: .available(version: "1.2.0"), pin: nil, install: .idle, location: .translocated),
                .download(version: "1.2.0", note: "Avsluta Sorla och öppna den från Program för att kunna installera uppdateringar inifrån Sorla.")
            )
        }
        let swedishStrings = try strings("sv")
        XCTAssertEqual(swedishStrings["Updates"], "Uppdateringar")
        XCTAssertEqual(swedishStrings["Speech model"], "Talmodell")
        XCTAssertEqual(swedishStrings["Check Now"], "Sök nu")
        XCTAssertEqual(swedishStrings["Check for updates now"], "Sök efter uppdateringar nu")
        XCTAssertEqual(swedishStrings["Try downloading the model again"], "Försök ladda ner modellen igen")
        XCTAssertEqual(swedishStrings["Check for updates automatically"], "Sök efter uppdateringar automatiskt")
        XCTAssertEqual(swedishStrings["Install updates automatically"], "Installera uppdateringar automatiskt")
        XCTAssertEqual(swedishStrings["Install and Relaunch"], "Installera och starta om")
    }

    // Sorla only knows it sent ⌘V, so VoiceOver hears the attempt, not a confirmed paste.
    func testTheKeepLastTranscriptionHintSaysWhatTheUserCanDo() throws {
        let key = "Keeps your latest text in memory for up to five minutes so you can paste it again with Paste Last Transcription. Turning this off forgets it at once."
        XCTAssertEqual(
            try strings("sv")[key],
            "Håller din senaste text i minnet i upp till fem minuter så att du kan klistra in den igen med Klistra in senaste transkriberingen. Stänger du av det glöms texten direkt."
        )
    }

    func testTheSuccessAnnouncementDescribesTheAttempt() throws {
        XCTAssertEqual(try strings("en")["Pasting text"], "Pasting text")
        XCTAssertEqual(try strings("sv")["Pasting text"], "Klistrar in texten")
        XCTAssertNil(try strings("en")["Pasted"])
    }

    // MARK: - Every key the app's views and SorlaCore use is translated (#14)

    private static let sources = resources.deletingLastPathComponent().appendingPathComponent("Sources")

    private func swiftFiles(_ target: String) throws -> [(name: String, text: String)] {
        let directory = Self.sources.appendingPathComponent(target)
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
            .map { ($0, try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8)) }
    }

    func testEveryLocalizedKeyInTheAppsViewsExistsInBothLanguages() throws {
        let english = try strings("en")
        let swedish = try strings("sv")
        var checked = 0
        for (name, text) in try swiftFiles("Sorla") {
            for key in try SourceStringKeys.localizedKeys(in: text, includeViews: true) {
                checked += 1
                XCTAssertTrue(key.isTranslated(in: english), "\(name): “\(key.pattern)” missing in en.lproj")
                XCTAssertTrue(key.isTranslated(in: swedish), "\(name): “\(key.pattern)” missing in sv.lproj")
            }
        }
        XCTAssertGreaterThan(checked, 60, "the scan found too few keys to be working")
    }

    func testEveryLocalizedKeyInSorlaCoreExistsInBothLanguages() throws {
        let english = try strings("en")
        let swedish = try strings("sv")
        var checked = 0
        for (name, text) in try swiftFiles("SorlaCore") {
            for key in try SourceStringKeys.localizedKeys(in: text, includeViews: false) {
                checked += 1
                XCTAssertTrue(key.isTranslated(in: english), "\(name): “\(key.pattern)” missing in en.lproj")
                XCTAssertTrue(key.isTranslated(in: swedish), "\(name): “\(key.pattern)” missing in sv.lproj")
            }
        }
        XCTAssertGreaterThan(checked, 50, "the scan found too few keys to be working")
    }

    func testTheSourceScanReadsInterpolationsEscapesAndLocalizedParameters() throws {
        let source = #"""
        func row(symbol: String, title: LocalizedStringKey, note: String) {}
        Text("Plain \"quoted\"")
        Text(verbatim: "Not a key")
        String(localized: "Version \(AppVersion.short ?? "—") (\(build))")
        row(symbol: "mic", title: "Microphone", note: "Not a key either")
        Toggle(SettingsRow.playSounds.title, isOn: $on)
        """#
        let keys = try SourceStringKeys.localizedKeys(in: source, includeViews: true)
        XCTAssertEqual(keys.map(\.pattern), [#"Plain "quoted""#, "Version \\(…) (\\(…))", "Microphone"])
        XCTAssertTrue(keys[1].isTranslated(in: ["Version %@ (%@)": ""]))
        XCTAssertFalse(keys[1].isTranslated(in: ["Version %@": ""]))
    }

    // English comes from en.lproj too, not from the key falling through.
    func testSettingsRowTitlesAreTranslated() throws {
        let englishTitles = try Localization.$bundle.withValue(languageBundle("en")) { SettingsRow.allCases.map(\.title) }
        let swedishTitles = try Localization.$bundle.withValue(swedish) { SettingsRow.allCases.map(\.title) }
        let englishTable = try strings("en")
        let swedishTable = try strings("sv")
        for (row, (en, sv)) in zip(SettingsRow.allCases, zip(englishTitles, swedishTitles)) {
            XCTAssertFalse(en.isEmpty, "\(row)")
            XCTAssertFalse(sv.isEmpty, "\(row)")
            if row != .appUpdates {
                XCTAssertNotEqual(en, sv, "\(row) has no Swedish title")
                XCTAssertTrue(englishTable.values.contains(en), "\(row): “\(en)” is not from en.lproj")
                XCTAssertTrue(swedishTable.values.contains(sv), "\(row): “\(sv)” is not from sv.lproj")
            }
        }
    }

    // A key copied into sv.lproj with its English text would pass the key checks, so Settings' own wording is compared.
    func testEverySettingsLabelAndAccessibleNameHasSwedishWording() throws {
        let english = try strings("en")
        let swedish = try strings("sv")
        var keys: [SourceStringKeys.Key] = []
        for file in ["Sorla/SettingsView.swift", "Sorla/ShortcutField.swift"] {
            keys += try SourceStringKeys.localizedKeys(in: String(contentsOf: Self.sources.appendingPathComponent(file), encoding: .utf8), includeViews: true)
        }
        for file in ["SorlaCore/SettingsRow.swift", "SorlaCore/UpdateRow.swift"] {
            keys += try SourceStringKeys.localizedKeys(in: String(contentsOf: Self.sources.appendingPathComponent(file), encoding: .utf8), includeViews: false)
        }
        let literals = keys.filter { !$0.parts.contains(nil) }.map(\.pattern)
        XCTAssertGreaterThan(literals.count, 30, "the scan found too few keys to be working")
        for key in literals {
            XCTAssertNotEqual(swedish[key], english[key], "“\(key)” reads the same in Swedish")
        }
        // The dynamic update rows' buttons are only read out by their full action.
        for key in ["Download the new version of Sorla", "Download the speech model", "Try downloading the model again", "Install Sorla and relaunch it", "Check for updates now"] {
            XCTAssertTrue(literals.contains(key), key)
        }
    }

    // VoiceOver reads these names on the two shortcut recorders (#12).
    func testSwedishShortcutFieldNames() throws {
        try Localization.$bundle.withValue(swedish) {
            XCTAssertEqual(SettingsRow.allCases.filter(\.isShortcutField).map(\.title), ["Kortkommando", "Klistra in senaste transkriberingen"])
        }
    }

    func testSwedishDiskSpaceUsesADecimalComma() throws {
        try Localization.$bundle.withValue(swedish) {
            XCTAssertEqual(
                ModelInstallError.insufficientDiskSpace(required: 1_376_514_942).reason,
                "Inte tillräckligt med ledigt utrymme (1,4 GB behövs)."
            )
        }
    }
}
