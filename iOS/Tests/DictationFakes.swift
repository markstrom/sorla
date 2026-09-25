import Foundation
@testable import Sorla

@MainActor
final class FakeRecorder: DictationRecorder {
    var onCaptureEnded: ((CaptureEnd) -> Void)?
    var startError: Error?
    var samples: [Float] = FakeRecorder.speech(seconds: 2)
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancels = 0
    private(set) var isCapturing = false

    func start() throws {
        if let startError { throw startError }
        starts += 1
        isCapturing = true
    }

    func stop() throws -> [Float] {
        stops += 1
        isCapturing = false
        return samples
    }

    func cancel() {
        cancels += 1
        isCapturing = false
    }

    // What an interruption or route change looks like to the coordinator.
    func endCapture(_ reason: CaptureEnd) {
        onCaptureEnded?(reason)
    }

    static func speech(seconds: Double) -> [Float] {
        (0..<Int(seconds * 16_000)).map { Float(sin(Double($0) / 20)) * 0.3 }
    }
}

@MainActor
final class FakeSystem: DictationSystem {
    var isMicrophoneAuthorized = true
    var isModelInstalled = true
    var isAppActive = false
    var sessionMarker: Date?
    var backgroundTimeRemaining: TimeInterval? = 25
    var canStartActivity = true
    private(set) var activityPhases: [DictationActivityPhase] = []
    private(set) var isActivityShowing = false
    private(set) var activityStarts = 0
    private(set) var backgroundTasks = 0
    private(set) var isBackgroundTaskRunning = false
    private(set) var metrics: [DictationMetric] = []
    private var expiration: (@MainActor () -> Void)?

    func startActivity() -> Bool {
        guard canStartActivity else { return false }
        activityStarts += 1
        isActivityShowing = true
        activityPhases.append(.listening)
        return true
    }

    func updateActivity(_ phase: DictationActivityPhase) {
        activityPhases.append(phase)
    }

    func endActivity() {
        isActivityShowing = false
    }

    func beginBackgroundTask(onExpiration: @escaping @MainActor () -> Void) {
        backgroundTasks += 1
        isBackgroundTaskRunning = true
        expiration = onExpiration
    }

    func endBackgroundTask() {
        isBackgroundTaskRunning = false
        expiration = nil
    }

    func expireBackgroundTime() {
        expiration?()
    }

    func record(_ metric: DictationMetric) {
        metrics.append(metric)
    }
}

@MainActor
final class FakeLimitWatch: RecordingLimitWatching {
    private(set) var isWatching = false
    private var onLimit: (@MainActor () -> Void)?

    func start(onWarning: @escaping @MainActor () -> Void, onLimit: @escaping @MainActor () -> Void) {
        isWatching = true
        self.onLimit = onLimit
    }

    func stop() {
        isWatching = false
        onLimit = nil
    }

    func reachLimit() {
        onLimit?()
    }
}

// Transcriptions finish only when the test says so, so no test waits on real time.
actor FakeTranscriber: TranscriptionEngine {
    enum Reply {
        case text(String)
        case failure
    }

    private var immediateReply: Reply?
    private var pending: [CheckedContinuation<Reply, Never>] = []
    private var callWaiters: [(count: Int, resume: CheckedContinuation<Void, Never>)] = []
    private(set) var transcribeCalls = 0
    private(set) var prepareCalls = 0
    private(set) var unloadCalls = 0
    private(set) var lastSampleCount = 0

    init(immediateReply: Reply? = nil) {
        self.immediateReply = immediateReply
    }

    private var prepareWaiters: [CheckedContinuation<Void, Never>] = []

    func prepare() async throws {
        prepareCalls += 1
        prepareWaiters.forEach { $0.resume() }
        prepareWaiters = []
    }

    func waitForPrepare() async {
        guard prepareCalls == 0 else { return }
        await withCheckedContinuation { prepareWaiters.append($0) }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        transcribeCalls += 1
        lastSampleCount = samples.count
        let count = transcribeCalls
        callWaiters.filter { $0.count <= count }.forEach { $0.resume.resume() }
        callWaiters.removeAll { $0.count <= count }
        let reply: Reply
        if let immediateReply {
            reply = immediateReply
        } else {
            reply = await withCheckedContinuation { pending.append($0) }
        }
        switch reply {
        case .text(let text): return text
        case .failure: throw CocoaError(.featureUnsupported)
        }
    }

    func unload() async {
        unloadCalls += 1
    }

    // Returns once transcribe has been called `count` times in total.
    func waitForTranscribeCall(_ count: Int = 1) async {
        guard transcribeCalls < count else { return }
        await withCheckedContinuation { callWaiters.append((count, $0)) }
    }

    func reply(_ reply: Reply) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume(returning: reply)
    }
}

// A time limit that passes only when the test fires it.
@MainActor
final class ManualTimeLimit {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requested: [Duration] = []

    func wait(_ duration: Duration) async {
        requested.append(duration)
        requestWaiters.forEach { $0.resume() }
        requestWaiters = []
        await withCheckedContinuation { waiters.append($0) }
    }

    // Returns once something is waiting for the limit, so firing it can't come too early.
    func waitUntilRequested() async {
        guard waiters.isEmpty else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func fire() {
        let waiting = waiters
        waiters = []
        waiting.forEach { $0.resume() }
    }
}

// A clock that moves only when the test moves it.
final class ManualClock {
    private(set) var now = ContinuousClock.now

    func advance(by duration: Duration) {
        now = now.advanced(by: duration)
    }
}
