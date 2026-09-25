import AppKit
import KeyboardShortcuts
import SorlaCore
import SwiftUI
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

    // MARK: - The shortcut fields in English and Swedish (#12, #13)

    private static let resources = settingsView
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources")

    private var languageBundleDirectories: [URL] = []

    // A bundle holding one .lproj, so that language resolves regardless of the Mac's languages.
    private func languageBundle(_ language: String) throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SorlaSettingsWindowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("\(language).lproj"),
            withDestinationURL: Self.resources.appendingPathComponent("\(language).lproj")
        )
        languageBundleDirectories.append(directory)
        return try XCTUnwrap(Bundle(url: directory))
    }

    override func tearDownWithError() throws {
        for directory in languageBundleDirectories {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func recorder(in view: NSView) -> KeyboardShortcuts.RecorderCocoa? {
        if let field = view as? KeyboardShortcuts.RecorderCocoa { return field }
        return view.subviews.lazy.compactMap { self.recorder(in: $0) }.first
    }

    // Rendered the way Settings does, so the wider frame (#13) can't drop the name the field gets (#12).
    func testTheWidenedShortcutFieldsAreNamedInEnglishAndSwedish() throws {
        let expected = [
            "en": ["Shortcut", "Paste last transcription"],
            "sv": ["Kortkommando", "Klistra in senaste transkriberingen"],
        ]
        for (language, titles) in expected {
            try Localization.$bundle.withValue(languageBundle(language)) {
                for (row, title) in zip([SettingsRow.customShortcut, .pasteLastShortcut], titles) {
                    let host = NSHostingView(rootView: ShortcutField(name: .init("sorlaSettingsWindowTests"), row: row)
                        .frame(width: SettingsView.recorderWidth))
                    host.frame = NSRect(x: 0, y: 0, width: 400, height: 60)
                    host.layoutSubtreeIfNeeded()

                    let field = try XCTUnwrap(recorder(in: host), "\(language) \(row)")
                    XCTAssertEqual(field.accessibilityLabel(), title, "\(language) \(row)")
                    XCTAssertEqual(field.frame.width, SettingsView.recorderWidth, "\(language) \(row)")
                }
            }
        }
    }

    // MARK: - Leaving Settings or a recording gives the shortcuts back (#14)

    // The app suspends the trigger and Paste Last while Settings is key and restores them on these reports.
    func testSettingsReportsWhenItTakesAndGivesBackTheKeys() {
        let (window, _) = windowWithAFocusableField()
        let controller = SettingsWindowController(window: window)
        var reports: [Bool] = []
        controller.onKeyStateChange = { reports.append($0) }

        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))

        XCTAssertEqual(reports, [true, false, true, false])
    }

    // A focused recorder pauses every KeyboardShortcuts hot key, including a custom trigger; this is its signal.
    private static let recorderActivity = Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange")

    private func recorderActivity(isActive: Bool) -> XCTestExpectation {
        expectation(forNotification: Self.recorderActivity, object: nil) { $0.userInfo?["isActive"] as? Bool == isActive }
    }

    private func windowRecordingAShortcut() async -> (SorlaWindow, KeyboardShortcuts.RecorderCocoa) {
        let field = KeyboardShortcuts.RecorderCocoa(shortcut: nil)
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        content.view.addSubview(field)
        let window = SettingsWindowController.makeWindow(content: content)
        let started = recorderActivity(isActive: true)
        XCTAssertTrue(window.makeFirstResponder(field))
        await fulfillment(of: [started], timeout: 1)
        return (window, field)
    }

    func testClearingSettingsFocusEndsARecordingSoTheHotKeysResume() async {
        let (window, _) = await windowRecordingAShortcut()
        let ended = recorderActivity(isActive: false)

        SettingsWindowController.clearInitialFocus(of: window) { _ in }

        await fulfillment(of: [ended], timeout: 1)
    }

    func testLeavingSettingsMidRecordingEndsItSoTheHotKeysResume() async {
        let (window, _) = await windowRecordingAShortcut()
        let ended = recorderActivity(isActive: false)

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)

        await fulfillment(of: [ended], timeout: 1)
    }
}
