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
                "Håll Höger ⌘ för att spela in"
            )
            XCTAssertEqual(
                TriggerHint.menuTitle(trigger: .customShortcut, mode: .toggle, customShortcut: "⌃⌥Space"),
                "Tryck på ⌃⌥Space för att spela in"
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
            XCTAssertEqual(SorlaIssue.microphoneMuted.menuTitle, "Mikrofonen verkar vara avstängd – kontrollera Ljud › Ingång")
            XCTAssertEqual(SorlaIssue.textOnClipboard(pasteShortcut: "⌃⌥V").menuTitle, "Texten ligger i urklippet – tryck ⌃⌥V")
            XCTAssertEqual(DictationCue(issue: .noInputDevice)?.announcement(pasteShortcut: nil), "Ingen mikrofon hittades")
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
