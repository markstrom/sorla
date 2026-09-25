import XCTest
import SorlaCore
@testable import Sorla

// Lightweight checks of the setup and recovery windows' wiring (#61, #72, #73); VoiceOver itself still needs a person.
final class RecoveryWindowTests: XCTestCase {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Sorla")

    private func source(_ file: String) throws -> String {
        try String(contentsOf: Self.sources.appendingPathComponent(file), encoding: .utf8)
    }

    // Voice Control users say what they see, so each button also answers to its visible title.
    func testEveryButtonAnswersToItsVisibleTitle() throws {
        for file in ["WelcomeView.swift", "RecoveryDialogController.swift"] {
            let buttons = try source(file).components(separatedBy: " Button(").dropFirst()
            XCTAssertGreaterThanOrEqual(buttons.count, 2, "\(file): the scan found too few buttons to be working")
            for button in buttons {
                XCTAssertTrue(button.contains(".accessibilityInputLabels("), "\(file): a button without input labels: \(button.prefix(60))")
            }
        }
    }

    // #73: the Welcome window's switches are the stored choices from Settings › Updates, install greyed out without
    // checks as there (c32ba97); the window itself never sets them or starts a check.
    func testTheWelcomeWindowsUpdateSwitchesAreTheSettingsOwn() throws {
        let welcome = try source("WelcomeView.swift") + source("WelcomeWindowController.swift")
        XCTAssertTrue(welcome.contains("autoCheckUpdates: $appSettings.autoCheckUpdates"))
        XCTAssertTrue(welcome.contains("autoInstallUpdates: $appSettings.autoInstallUpdates"))
        XCTAssertTrue(welcome.contains(".disabled(!autoCheckUpdates)"))
        XCTAssertTrue(welcome.contains("SettingsRow.autoCheckUpdates.title"))
        XCTAssertTrue(welcome.contains("SettingsRow.autoInstallUpdates.title"))
        XCTAssertFalse(welcome.contains("autoCheckUpdates ="))
        XCTAssertFalse(welcome.contains("autoInstallUpdates ="))
        XCTAssertFalse(welcome.contains("checkNow"))
        XCTAssertFalse(welcome.contains("updateChecker"))
    }

    // #72: a dialog's Return key waits a moment, so a key meant for the app the user was in doesn't answer it.
    func testTheDialogsDefaultButtonIsBoundToTheArmedState() throws {
        let dialog = try source("RecoveryDialogController.swift")
        XCTAssertTrue(dialog.contains(".keyboardShortcut(model.isDefaultButtonArmed ? .defaultAction : nil)"))
        XCTAssertTrue(dialog.contains(".task(id: model.presentation)"))
    }

    @MainActor
    func testReturnIsArmedOnlyAfterTheDelay() async {
        let model = RecoveryDialogModel(dialog: .microphoneStart)
        var slept: [Duration] = []
        model.present(.microphoneStart)
        XCTAssertFalse(model.isDefaultButtonArmed)
        await model.armDefaultButton(for: model.presentation, after: RecoveryDialog.defaultButtonDelay) { slept.append($0) }
        XCTAssertEqual(slept, [RecoveryDialog.defaultButtonDelay])
        XCTAssertTrue(model.isDefaultButtonArmed)
    }

    // The same dialog brought forward by a second blocked press, or reopened after a close, starts the delay over.
    @MainActor
    func testShowingTheSameDialogAgainDisarmsReturn() async {
        let model = RecoveryDialogModel(dialog: .microphoneStart)
        let restart = RecoveryDialog.restart(canRestart: true, isTextOnClipboard: false)
        model.present(restart)
        await model.armDefaultButton(for: model.presentation, after: .zero) { _ in }
        XCTAssertTrue(model.isDefaultButtonArmed)

        let first = model.presentation
        model.present(restart)
        XCTAssertFalse(model.isDefaultButtonArmed, "Return must not answer a dialog that just came forward")
        XCTAssertNotEqual(model.presentation, first)
    }

    // A wait left over from an earlier presentation doesn't arm the new one early.
    @MainActor
    func testAnEarlierPresentationsWaitDoesNotArmTheNewOne() async {
        let model = RecoveryDialogModel(dialog: .microphoneStart)
        model.present(.microphoneStart)
        let stale = model.presentation
        model.present(.microphoneStart)
        await model.armDefaultButton(for: stale, after: .zero) { _ in }
        XCTAssertFalse(model.isDefaultButtonArmed)
        await model.armDefaultButton(for: model.presentation, after: .zero) { _ in }
        XCTAssertTrue(model.isDefaultButtonArmed)
    }
}
