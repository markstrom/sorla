import AppKit
import KeyboardShortcuts
import SorlaCore
import XCTest
@testable import Sorla

// Lightweight checks of the Settings window's wiring (#14); VoiceOver itself still needs a person.
@MainActor
final class SettingsWindowTests: XCTestCase {
    private static let settingsView = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Sorla/SettingsView.swift")

    private func settingsSource() throws -> String {
        try String(contentsOf: Self.settingsView, encoding: .utf8)
    }

    // MARK: - Every row has a label

    func testEveryToggleAndPickerAndLabeledRowIsLabelledByASettingsRow() throws {
        let source = try settingsSource()
        let controls = try Regex(#"\b(Toggle|Picker|LabeledContent)\(\s*([^,){]*)"#, as: (Substring, Substring, Substring).self)
        let matches = source.matches(of: controls)
        XCTAssertGreaterThanOrEqual(matches.count, 11, "the scan found too few rows to be working")
        for match in matches {
            let label = match.output.2
            XCTAssertTrue(label.hasPrefix("SettingsRow.") && label.hasSuffix(".title"), "\(source[match.range]) has no row title")
        }
    }

    func testEverySettingsRowIsShownInSettings() throws {
        let source = try settingsSource()
        for row in SettingsRow.allCases {
            XCTAssertTrue(source.contains("SettingsRow.\(row).title") || source.contains(".\(row),") || source.contains("row: .\(row)"), "\(row) is not used")
            XCTAssertFalse(row.title.isEmpty, "\(row)")
        }
    }

    // MARK: - The shortcut fields have accessible names (#12)

    func testEachShortcutFieldIsNamedAfterItsRow() {
        let rows = SettingsRow.allCases.filter(\.isShortcutField)
        XCTAssertEqual(rows, [.customShortcut, .pasteLastShortcut])
        for row in rows {
            let field = KeyboardShortcuts.RecorderCocoa(shortcut: nil)
            XCTAssertNil(field.accessibilityLabel())

            ShortcutField.giveAccessibleName(to: field, from: row)

            XCTAssertEqual(field.accessibilityLabel(), row.title)
            XCTAssertFalse(row.title.isEmpty)
        }
    }

    func testTheShortcutFieldsInSettingsUseTheirRows() throws {
        let source = try settingsSource()
        XCTAssertTrue(source.contains("ShortcutField(name: .sorlaCustomTrigger, row: .customShortcut)"))
        XCTAssertTrue(source.contains("ShortcutField(name: .pasteLastTranscription, row: .pasteLastShortcut)"))
    }

    // MARK: - No initial first responder (#36)

    private func windowWithAFocusableField() -> (SorlaWindow, NSTextField) {
        let field = NSTextField(string: "")
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        content.view.addSubview(field)
        return (SettingsWindowController.makeWindow(content: content), field)
    }

    func testTheSettingsWindowHasNoInitialFirstResponder() {
        let (window, _) = windowWithAFocusableField()
        XCTAssertEqual(window.title, SettingsView.windowTitle)
        XCTAssertNil(window.initialFirstResponder)
        XCTAssertFalse(window.isVisible)
    }

    func testShowingClearsAFocusedFieldNowAndAgainOnTheNextTurn() {
        let (window, field) = windowWithAFocusableField()
        XCTAssertTrue(window.makeFirstResponder(field))
        var nextTurn: [@MainActor () -> Void] = []

        SettingsWindowController.clearInitialFocus(of: window) { nextTurn.append($0) }
        XCTAssertTrue(window.firstResponder === window)

        // SwiftUI hands out its initial focus a turn later.
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertEqual(nextTurn.count, 1)
        nextTurn.forEach { $0() }

        XCTAssertTrue(window.firstResponder === window)
    }
}
