import XCTest
@testable import SorlaCore

@MainActor
final class ModifierReleaseTests: XCTestCase {
    private let clock = TestClock()
    private var heldPolls = 0

    private func startWaiting() -> Task<PasteLastPreparation, Never> {
        let clock = self.clock
        return Task { @MainActor in
            await ModifierRelease.wait(
                isHeld: { [unowned self] in
                    guard heldPolls > 0 else { return false }
                    heldPolls -= 1
                    return true
                },
                now: { clock.now },
                sleep: { await clock.sleep(for: $0) }
            )
        }
    }

    private func poll(times: Int) async {
        for poll in 1...times {
            await clock.waitForSleeps(poll)
            await clock.advance(by: ModifierRelease.pollInterval)
        }
    }

    func testKeysLetGoBeforeTheDeadlineArePasted() async {
        heldPolls = 10
        let wait = startWaiting()

        await poll(times: 10)

        let result = await wait.value
        XCTAssertEqual(result, .ready)
        XCTAssertEqual(clock.sleeps.count, 10)
    }

    func testKeysNotHeldAtAllPasteAtOnce() async {
        let result = await startWaiting().value

        XCTAssertEqual(result, .ready)
        XCTAssertEqual(clock.sleeps, [])
    }

    func testKeysHeldPastTheDeadlineAreNotPasted() async {
        heldPolls = .max
        let wait = startWaiting()

        await poll(times: 50)

        let result = await wait.value
        XCTAssertEqual(result, .keysStillHeld)
        XCTAssertEqual(clock.sleeps.count, 50)
    }

    func testCancellingTheWaitAbandonsThePaste() async {
        heldPolls = .max
        let wait = startWaiting()
        await clock.waitForSleeps(1)

        wait.cancel()
        await clock.advance(by: ModifierRelease.pollInterval)

        let result = await wait.value
        XCTAssertEqual(result, .abandoned)
    }
}
