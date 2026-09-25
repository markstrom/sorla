import XCTest
@testable import Sorla

// Lightweight checks of the setup and recovery windows' wiring (#61, #72); VoiceOver itself still needs a person.
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
            let buttons = try source(file).components(separatedBy: "Button(").dropFirst()
            XCTAssertGreaterThanOrEqual(buttons.count, 2, "\(file): the scan found too few buttons to be working")
            for button in buttons {
                XCTAssertTrue(button.contains(".accessibilityInputLabels("), "\(file): a button without input labels: \(button.prefix(60))")
            }
        }
    }

    // #72: a dialog's Return key waits a moment, so a key meant for the app the user was in doesn't answer it.
    func testTheDialogsDefaultButtonIsArmedOnlyAfterADelay() throws {
        let dialog = try source("RecoveryDialogController.swift")
        XCTAssertTrue(dialog.contains(".keyboardShortcut(isDefaultButtonArmed ? .defaultAction : nil)"))
        XCTAssertTrue(dialog.contains("RecoveryDialog.defaultButtonDelay"))
    }
}
