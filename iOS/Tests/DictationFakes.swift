import Foundation
@testable import Sorla

@MainActor
final class FakeRecorder: DictationRecorder {
    var onCaptureEnded: ((CaptureEnd) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var startError: Error?
    // What the real recorder reports about the session when it starts.
    var startDiagnostic: String? = "session: category record"
    var samples: [Float] = FakeRecorder.speech(seconds: 2)
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancels = 0
    private(set) var isCapturing = false

    func start() throws {
        if let startDiagnostic { onDiagnostic?(startDiagnostic) }
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

    func diagnose(_ detail: String) {
        onDiagnostic?(detail)
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
    // What waiting for the app to become active finds, after the intent asked to continue in the foreground.
    var becomesActive = true
    private(set) var activeWaits = 0
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

    func waitUntilActive() async -> Bool {
        activeWaits += 1
        if becomesActive { isAppActive = true }
        return isAppActive
    }
}

// The intent's view of the foreground. `continueInForeground` can be held until the test lets it go.
@MainActor
final class FakeForeground: ForegroundTransition {
    var isRunningInBackground = true
    var canContinueInForeground = true
    var error: Error?
    var holds = false
    // Whatever the test wants to know at the moment Sorla is asked to come forward.
    var onContinue: (() -> Void)?
    private(set) var continues = 0
    private var held: CheckedContinuation<Void, Never>?
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []

    func continueInForeground() async throws {
        continues += 1
        onContinue?()
        if holds {
            await withCheckedContinuation { continuation in
                held = continuation
                heldWaiters.forEach { $0.resume() }
                heldWaiters = []
            }
        }
        if let error { throw error }
    }

    // Returns once `continueInForeground` is being held.
    func waitUntilHeld() async {
        guard held == nil else { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }

    func release() {
        held?.resume()
        held = nil
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

// The audio session as the recorder drives it; every call lands in a shared log so order can be checked.
@MainActor
final class FakeAudioSession: DictationAudioSession {
    var activationError: Error?
    var snapshotValue = AudioSessionSnapshot(
        category: .record, mode: .default, options: [.allowBluetoothHFP],
        inputPort: .builtInMic, sampleRate: 48_000, inputChannels: 1
    )
    private(set) var configurations: [DictationSessionConfiguration] = []
    private(set) var isActive = false
    let calls: CallLog

    init(calls: CallLog) {
        self.calls = calls
    }

    func configure(_ configuration: DictationSessionConfiguration) throws {
        calls.append("configure")
        configurations.append(configuration)
    }

    func activate() throws {
        calls.append("activate")
        if let activationError { throw activationError }
        isActive = true
    }

    func deactivate() {
        calls.append("deactivate")
        isActive = false
    }

    func snapshot() -> AudioSessionSnapshot {
        snapshotValue
    }
}

final class CallLog {
    private(set) var entries: [String] = []
    func append(_ entry: String) { entries.append(entry) }
    func clear() { entries = [] }
}

// A microphone with one engine that lives until it is discarded, delivering exactly the frames a test hands it,
// on the test's thread.
final class FakeAudioInput: DictationAudioInput {
    var sampleRate: Double = 16_000
    var prepareError: Error?
    // Whether the next resume fails; a rate change is taken from `sampleRate`.
    var resumeFails = false
    private(set) var prepares = 0
    private(set) var enginesMade = 0
    private(set) var resumes = 0
    private(set) var discards = 0
    private(set) var isRunning = false
    private(set) var preparation = "no engine"
    private var hasEngine = false
    private var runningRate: Double = 0
    private var onFrames: ((UnsafeBufferPointer<Float>) -> Void)?
    let calls: CallLog

    init(calls: CallLog) {
        self.calls = calls
    }

    func prepare() throws -> Double {
        calls.append("prepareInput")
        if !hasEngine {
            hasEngine = true
            enginesMade += 1
        }
        preparation = "engine \(enginesMade), \(Int(sampleRate)) Hz"
        if let prepareError { throw prepareError }
        prepares += 1
        runningRate = sampleRate
        return sampleRate
    }

    func start(onFrames: @escaping (UnsafeBufferPointer<Float>) -> Void) throws {
        calls.append("startInput")
        self.onFrames = onFrames
        isRunning = true
    }

    func stop() {
        isRunning = false
        onFrames = nil
    }

    func resume() -> InputResumption {
        resumes += 1
        let onFrames = self.onFrames
        stop()
        if resumeFails { return .failed("test") }
        guard sampleRate == runningRate else { return .rateChanged }
        self.onFrames = onFrames
        isRunning = true
        return .continued
    }

    func discardEngine() {
        discards += 1
        stop()
        hasEngine = false
    }

    func deliver(_ frames: [Float]) {
        frames.withUnsafeBufferPointer { onFrames?($0) }
    }

    func deliver(seconds: Double, level: Float) {
        deliver(Array(repeating: level, count: Int(seconds * sampleRate)))
    }
}

// A clock that moves only when the test moves it.
final class ManualClock {
    private(set) var now = ContinuousClock.now

    func advance(by duration: Duration) {
        now = now.advanced(by: duration)
    }
}
