import SorlaCore
import SwiftUI
import XCTest
@testable import Sorla

// #75: key names become chips inside the one text run, and the sentence itself is unchanged in both languages.
final class KeycapTextTests: XCTestCase {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources")

    private var directories: [URL] = []

    override func tearDownWithError() throws {
        for directory in directories { try FileManager.default.removeItem(at: directory) }
    }

    private func languageBundle(_ language: String) throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SorlaKeycapTextTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("\(language).lproj"),
            withDestinationURL: Self.resources.appendingPathComponent("\(language).lproj")
        )
        directories.append(directory)
        return try XCTUnwrap(Bundle(url: directory))
    }

    private func assertChip(_ plain: String, key: String, file: StaticString = #filePath, line: UInt = #line) {
        let attributed = KeycapText.attributed(plain, keys: [key], font: .system(.callout, design: .monospaced))
        XCTAssertEqual(KeycapText.plain(attributed), plain, file: file, line: line)
        let styled = attributed.runs.filter { $0.swiftUI.backgroundColor != nil }
        XCTAssertEqual(styled.count, 1, plain, file: file, line: line)
        for run in styled {
            XCTAssertNotNil(run.swiftUI.font, file: file, line: line)
            let text = String(attributed[run.range].characters)
            XCTAssertEqual(KeycapText.plain(AttributedString(text)).trimmingCharacters(in: .whitespaces), key, file: file, line: line)
            XCTAssertFalse(text.contains(" "), "the key never breaks across lines: \(text)", file: file, line: line)
        }
        let unstyled = attributed.runs.filter { $0.swiftUI.backgroundColor == nil }
        XCTAssertTrue(unstyled.allSatisfy { $0.swiftUI.font == nil }, file: file, line: line)
    }

    func testTheTriggerAndPasteShortcutsAreChipsInBothLanguages() throws {
        for language in ["en", "sv"] {
            try Localization.$bundle.withValue(languageBundle(language)) {
                for trigger in [TriggerKey.rightCommand, .fn] {
                    for mode in RecordingMode.allCases {
                        let key = TriggerHint.keyLabel(for: trigger, customShortcut: nil)
                        assertChip(WelcomeChecklist.readinessLine(isReady: true, trigger: trigger, mode: mode, customShortcut: nil), key: key)
                    }
                }
                assertChip(BlockedPasteNote.onClipboard.message, key: "⌘V")
                assertChip(BlockedPasteNote.pasteLastHint(.shortcut("⌃⌥V")), key: "⌃⌥V")
                // With VoiceOver the note names the menu item and VO-M instead (#64).
                assertChip(BlockedPasteNote.pasteLastHint(.menu), key: PasteLastRoute.menu.keys)
            }
        }
    }

    func testTextWithoutAKeyIsLeftAlone() {
        let plain = "Fix the items above to try dictation."
        let attributed = KeycapText.attributed(plain, keys: [nil, "Right ⌘"], font: .body)
        XCTAssertEqual(String(attributed.characters), plain)
        XCTAssertTrue(attributed.runs.allSatisfy { $0.swiftUI.backgroundColor == nil })
    }
}
