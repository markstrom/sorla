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

    private var swedishBundleDirectory: URL?

    // A bundle holding only sv.lproj, so Swedish is its preferred localization regardless of the Mac's languages.
    private var swedish: Bundle {
        get throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SorlaLocalizationTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: directory.appendingPathComponent("sv.lproj"),
                withDestinationURL: Self.resources.appendingPathComponent("sv.lproj")
            )
            swedishBundleDirectory = directory
            return try XCTUnwrap(Bundle(url: directory))
        }
    }

    override func tearDownWithError() throws {
        if let swedishBundleDirectory {
            try FileManager.default.removeItem(at: swedishBundleDirectory)
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
        }
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
                MenuStatusRow.current(microphoneDenied: false, accessibilityMissing: false, model: .upToDate(version: "1"), modelLoadFailed: false, appUpdate: "1.2.0")?.title,
                "Sorla 1.2.0 finns – Ladda ner"
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

    func testSettingsRowTitlesAreTranslated() throws {
        let english = SettingsRow.allCases.map(\.title)
        let swedishTitles = try Localization.$bundle.withValue(swedish) { SettingsRow.allCases.map(\.title) }
        for (row, (en, sv)) in zip(SettingsRow.allCases, zip(english, swedishTitles)) {
            XCTAssertFalse(en.isEmpty, "\(row)")
            XCTAssertFalse(sv.isEmpty, "\(row)")
            if row != .appUpdates {
                XCTAssertNotEqual(en, sv, "\(row) has no Swedish title")
            }
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
