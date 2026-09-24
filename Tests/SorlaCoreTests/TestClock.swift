import Foundation

// Time moves only when a test advances it, and advancing returns once every sleeper it woke has run on.
@MainActor
final class TestClock {
    private(set) var now = ContinuousClock.now
    private(set) var sleeps: [Duration] = []
    private var sleepers: [(deadline: ContinuousClock.Instant, wake: CheckedContinuation<Void, Never>)] = []
    private var sleepWaiters: [(count: Int, resume: CheckedContinuation<Void, Never>)] = []
    private var waking = 0
    private var allWoken: CheckedContinuation<Void, Never>?

    nonisolated init() {}

    func sleep(for duration: Duration) async {
        sleeps.append(duration)
        let count = sleeps.count
        sleepWaiters.filter { $0.count <= count }.forEach { $0.resume.resume() }
        sleepWaiters.removeAll { $0.count <= count }
        await withCheckedContinuation { sleepers.append((now + duration, $0)) }
        waking -= 1
        if waking == 0 {
            allWoken?.resume()
            allWoken = nil
        }
    }

    // Returns once `count` sleeps have started, counting from the clock's creation.
    func waitForSleeps(_ count: Int) async {
        guard sleeps.count < count else { return }
        await withCheckedContinuation { sleepWaiters.append((count, $0)) }
    }

    func advance(by duration: Duration) async {
        now += duration
        while true {
            let now = self.now
            let due = sleepers.filter { $0.deadline <= now }
            guard !due.isEmpty else { return }
            sleepers.removeAll { $0.deadline <= now }
            waking = due.count
            await withCheckedContinuation { done in
                allWoken = done
                due.forEach { $0.wake.resume() }
            }
        }
    }
}
