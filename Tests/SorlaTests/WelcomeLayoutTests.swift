import AppKit
import SorlaCore
import SwiftUI
import XCTest
@testable import Sorla

// Lays the Welcome / Set Up Sorla page out offscreen in both languages (#73, #75); how it looks still needs a person.
@MainActor
final class WelcomeLayoutTests: XCTestCase {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources")

    private var bundleDirectories: [URL] = []

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    override func tearDownWithError() throws {
        for directory in bundleDirectories {
            try FileManager.default.removeItem(at: directory)
        }
    }

    // A bundle holding one .lproj, so that language is used regardless of the Mac's languages.
    private func languageBundle(_ language: String) throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SorlaWelcomeLayoutTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("\(language).lproj"),
            withDestinationURL: Self.resources.appendingPathComponent("\(language).lproj")
        )
        bundleDirectories.append(directory)
        return try XCTUnwrap(Bundle(url: directory))
    }

    // Each language, with the longer macOS 27 name for the Accessibility pane.
    private func inEachLanguage(_ body: (String) throws -> Void) throws {
        for language in ["en", "sv"] {
            let bundle = try languageBundle(language)
            try Localization.$bundle.withValue(bundle) {
                try AccessibilityPaneName.$systemMajorVersion.withValue(27) {
                    try body(language)
                }
            }
        }
    }

    private func content(
        microphone: MicrophoneAccess = .granted,
        isTrusted: Bool = true,
        model: WelcomeRowStatus = .done,
        isTextOnClipboard: Bool = false
    ) -> WelcomeContent {
        WelcomeContent(
            microphone: WelcomeChecklist.microphoneRow(microphone),
            accessibility: WelcomeChecklist.accessibilityRow(isTrusted: isTrusted),
            model: model,
            isTextOnClipboard: isTextOnClipboard,
            isAccessibilityTrusted: isTrusted,
            readyLine: WelcomeChecklist.readinessLine(isReady: true, trigger: .rightCommand, mode: .pushToTalk, customShortcut: nil),
            toggleModeTip: WelcomeChecklist.toggleModeTip(mode: .pushToTalk)
        )
    }

    private func size(
        _ content: WelcomeContent,
        autoCheck: Binding<Bool> = .constant(false),
        autoInstall: Binding<Bool> = .constant(false)
    ) -> NSSize {
        let host = NSHostingView(rootView: WelcomePage(
            content: content,
            autoCheckUpdates: autoCheck,
            autoInstallUpdates: autoInstall,
            perform: { _ in },
            announce: { _ in },
            onDone: {}
        ))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        return size
    }

    // #75: a checkmark turning into a button, a note appearing or the model moving on must not move anything.
    func testTheWindowKeepsItsSizeWhateverStateTheRowsAreIn() throws {
        try inEachLanguage { language in
            let expected = size(content())
            XCTAssertEqual(expected.width, WelcomePage.width, language)
            for microphone in [MicrophoneAccess.granted, .notDetermined, .denied] {
                for isTrusted in [true, false] {
                    let downloading = WelcomeChecklist.modelRow(isInstalled: false, isLoaded: false, loadFailed: false, model: .downloading(version: "1", fraction: 0.07, isUpdate: false))
                    for model in WelcomeRow.model.possibleStatuses + [downloading] {
                        let actual = size(content(microphone: microphone, isTrusted: isTrusted, model: model))
                        XCTAssertEqual(actual, expected, "\(language): \(microphone), trusted \(isTrusted), \(model)")
                    }
                }
            }
        }
    }

    // #72, #75: granting access while the note about the clipboard shows changes its wording, not its size.
    func testTheClipboardNoteKeepsItsSizeWhenAccessIsGranted() throws {
        try inEachLanguage { language in
            XCTAssertEqual(
                size(content(isTrusted: false, isTextOnClipboard: true)),
                size(content(isTrusted: true, isTextOnClipboard: true)),
                language
            )
        }
    }

    func testTurningTheUpdateSwitchesOnDoesNotMoveAnything() throws {
        try inEachLanguage { language in
            let expected = size(content())
            for (check, install) in [(true, false), (true, true), (false, true)] {
                XCTAssertEqual(size(content(), autoCheck: .constant(check), autoInstall: .constant(install)), expected, "\(language): \(check), \(install)")
            }
        }
    }

    // #75: buttons keep their full title; the row's text gives way instead, and keeps enough room to read.
    func testEveryButtonFitsWithItsFullTitleInBothLanguages() throws {
        try inEachLanguage { language in
            let titles = WelcomeRow.allCases.flatMap(\.possibleStatuses).compactMap(\.buttonTitle)
            XCTAssertFalse(titles.isEmpty)
            for title in titles {
                let width = NSHostingView(rootView: Button(title) {}).fittingSize.width
                XCTAssertGreaterThan(width, 20, title)
                XCTAssertLessThanOrEqual(width, WelcomePage.widestButtonAllowed, "\(language): \(title)")
            }
        }
    }

    // #73: showing the window, in any state, never writes either update setting; only a click on a switch does.
    func testShowingTheWindowNeverChangesTheUpdateSettings() throws {
        var writes: [String] = []
        let autoCheck = Binding(get: { false }, set: { _ in writes.append("autoCheckUpdates") })
        let autoInstall = Binding(get: { true }, set: { _ in writes.append("autoInstallUpdates") })
        try inEachLanguage { _ in
            _ = size(content(), autoCheck: autoCheck, autoInstall: autoInstall)
            _ = size(content(microphone: .denied, isTrusted: false, model: .inProgress("…")), autoCheck: autoCheck, autoInstall: autoInstall)
        }
        XCTAssertEqual(writes, [])
    }
}
