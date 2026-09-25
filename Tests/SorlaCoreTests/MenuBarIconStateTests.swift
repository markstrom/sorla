import XCTest
@testable import SorlaCore

// #76: the menu bar icon shows at a glance when something blocks dictation.
final class MenuBarIconStateTests: XCTestCase {
    private func icon(ready: Bool = true, phase: DictationPhase = .idle, _ problems: Set<RecoveryProblem> = []) -> MenuBarIconState {
        MenuBarIconState.current(isModelReady: ready, phase: phase, problems: problems)
    }

    private static let blockers: [RecoveryProblem] = [
        .microphoneAccess,
        .accessibility,
        .model(.missing),
        .model(.downloadFailed),
        .model(.insufficientDiskSpace),
        .model(.loadFailed),
    ]

    func testEveryBlockerFromTheSetupChecklistBadgesTheIcon() {
        for problem in Self.blockers {
            let icon = icon([problem])
            XCTAssertEqual(icon.badge, .attention, "\(problem)")
            XCTAssertEqual(icon.accessibilityDescription, "Sorla (needs attention)", "\(problem)")
        }
    }

    func testNothingWrongMeansNoBadge() {
        XCTAssertEqual(icon(), MenuBarIconState(mark: .ready, badge: nil, accessibilityDescription: "Sorla"))
        XCTAssertEqual(icon(phase: .recording).accessibilityDescription, "Sorla (recording)")
        XCTAssertEqual(icon(phase: .transcribing).accessibilityDescription, "Sorla (transcribing)")
    }

    // A model on its way is waited for: the ring, no badge.
    func testALoadingModelShowsTheRingWithoutABadge() {
        for phase in [DictationPhase.idle, .recording, .transcribing] {
            XCTAssertEqual(icon(ready: false, phase: phase), MenuBarIconState(mark: .notReady, badge: nil, accessibilityDescription: "Sorla (loading model)"))
        }
    }

    // A failed load has the badge, not a glyph of its own, so the icon never shows two warnings at once.
    func testAFailedModelIsTheRingWithTheBadge() {
        XCTAssertEqual(
            icon(ready: false, [.model(.loadFailed)]),
            MenuBarIconState(mark: .notReady, badge: .attention, accessibilityDescription: "Sorla (needs attention)")
        )
    }

    // The mark still follows the model, so a missing permission leaves the dot.
    func testAPermissionBadgesTheReadyMark() {
        XCTAssertEqual(icon([.accessibility]).mark, .ready)
        XCTAssertEqual(icon(phase: .recording, [.accessibility]).badge, .attention)
    }

    func testTheRestartBadgeWins() {
        for problem in Self.blockers {
            let icon = icon([problem, .restartRequired])
            XCTAssertEqual(icon.badge, .restart, "\(problem)")
            XCTAssertEqual(icon.accessibilityDescription, "Sorla (needs a restart)")
        }
        XCTAssertEqual(icon(ready: false, [.restartRequired]), MenuBarIconState(mark: .notReady, badge: .restart, accessibilityDescription: "Sorla (needs a restart)"))
    }

    // Its dialog explained it when it happened, and the input may be back; the menu row still says so.
    func testAMicrophoneThatFailedToStartDoesNotBadgeTheIcon() {
        XCTAssertNil(icon([.microphoneStart]).badge)
    }

    // The badge comes from the same checks as the setup window, so a denied microphone counts but one not yet asked doesn't.
    func testTheBadgeFollowsTheRecoveryChecks() {
        let problems = RecoveryProblem.current(
            isMicrophoneAccessDenied: false,
            isAccessibilityTrusted: true,
            model: DictationGate.modelProblem(isModelInstalled: false, model: .downloading(version: "1", fraction: 0.5, isUpdate: false)),
            didMicrophoneFailToStart: false,
            isAppReplaced: false
        )
        XCTAssertNil(icon(ready: false, problems).badge, "a download on its way needs nothing from the user")
        let missing = RecoveryProblem.current(
            isMicrophoneAccessDenied: false,
            isAccessibilityTrusted: true,
            model: DictationGate.modelProblem(isModelInstalled: false, model: .notInstalled),
            didMicrophoneFailToStart: false,
            isAppReplaced: false
        )
        XCTAssertEqual(icon(ready: false, missing).badge, .attention)
    }

    // Each blocker's menu row opens the setup window, where its fix is.
    func testEveryBadgedBlockersMenuRowOpensTheSetupWindow() {
        let rows = [
            MenuStatusRow.current(microphoneDenied: true, accessibilityMissing: false, model: .upToDate(version: "1"), modelLoadFailed: false),
            MenuStatusRow.current(microphoneDenied: false, accessibilityMissing: true, model: .upToDate(version: "1"), modelLoadFailed: false),
            MenuStatusRow.current(microphoneDenied: false, accessibilityMissing: false, model: .notInstalled, modelLoadFailed: false),
            MenuStatusRow.current(microphoneDenied: false, accessibilityMissing: false, model: .failed(.network, isUpdate: false), modelLoadFailed: false),
            MenuStatusRow.current(microphoneDenied: false, accessibilityMissing: false, model: .failed(.insufficientDiskSpace(required: 1), isUpdate: false), modelLoadFailed: false),
            MenuStatusRow.current(microphoneDenied: false, accessibilityMissing: false, model: .upToDate(version: "1"), modelLoadFailed: true),
        ]
        for row in rows {
            XCTAssertEqual(row?.action, .showWelcome, "\(String(describing: row))")
        }
    }
}
