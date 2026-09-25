import Foundation

// The microphone side of a dictation. `stop` returns 16 kHz mono samples and closes the microphone.
@MainActor
protocol DictationRecorder: AnyObject {
    var onCaptureEnded: ((CaptureEnd) -> Void)? { get set }
    func start() throws
    func stop() throws -> [Float]
    func cancel()
}

// Everything the coordinator needs from iOS, so the state model runs in tests without it.
@MainActor
protocol DictationSystem: AnyObject {
    var isMicrophoneAuthorized: Bool { get }
    var isModelInstalled: Bool { get }
    var isAppActive: Bool { get }
    // Persisted across processes: a marker left behind means the recording process died.
    var sessionMarker: Date? { get set }
    var backgroundTimeRemaining: TimeInterval? { get }
    func startActivity() -> Bool
    func updateActivity(_ phase: DictationActivityPhase)
    func endActivity()
    func beginBackgroundTask(onExpiration: @escaping @MainActor () -> Void)
    func endBackgroundTask()
    func record(_ metric: DictationMetric)
}

@MainActor
protocol RecordingLimitWatching: AnyObject {
    func start(onWarning: @escaping @MainActor () -> Void, onLimit: @escaping @MainActor () -> Void)
    func stop()
}

extension RecordingLimitWatch: RecordingLimitWatching {}

// Numbers only: never audio, never transcript text.
struct DictationMetric: Codable, Equatable, Sendable {
    var date: Date
    var outcome: String
    var appWasActive: Bool
    var invocationToListeningMs: Double?
    var stopToResultMs: Double?
    var audioSeconds: Double?
    var backgroundSecondsRemainingAtStop: Double?
    var modelWasReadyAtStop: Bool?
    var captureEnd: String?
}

// One toggle for start and stop. All state lives on the main actor, so triggers are handled one at a time
// and a trigger during transcription is answered with `.busy` instead of starting or copying anything.
@MainActor
final class DictationCoordinator {
    // Generous, since a slow phone is not a hung one; it only has to end a wait that would never end.
    nonisolated static func transcriptionTimeLimit(audioSeconds: Double) -> Duration {
        .seconds(max(30, 3 * audioSeconds))
    }

    private(set) var phase: DictationPhase = .idle
    private(set) var isModelReady = false

    private let recorder: DictationRecorder
    private let transcriber: TranscriptionEngine
    private let system: DictationSystem
    private let limitWatch: RecordingLimitWatching
    private let now: () -> ContinuousClock.Instant
    private let waitForTimeLimit: @MainActor (Duration) async -> Void

    private var capturedSamples: [Float]?
    private var captureEnd: CaptureEnd?
    private var pending: PendingTranscription?
    private var preload: Task<Void, Never>?

    init(
        recorder: DictationRecorder,
        transcriber: TranscriptionEngine,
        system: DictationSystem,
        limitWatch: RecordingLimitWatching,
        now: @escaping () -> ContinuousClock.Instant = { .now },
        waitForTimeLimit: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.system = system
        self.limitWatch = limitWatch
        self.now = now
        self.waitForTimeLimit = waitForTimeLimit
        recorder.onCaptureEnded = { [weak self] reason in self?.endCapture(reason) }
    }

    func toggle() async -> DictationOutcome {
        let invokedAt = now()
        switch phase {
        case .idle:
            return start(invokedAt: invokedAt)
        case .listening, .captured:
            return await stop(invokedAt: invokedAt)
        case .transcribing:
            system.record(metric(.busy))
            return .busy
        }
    }

    // Returns whether there was anything to cancel. A running transcription's result is dropped, never delivered.
    @discardableResult
    func cancel() -> Bool {
        switch phase {
        case .idle:
            return false
        case .listening:
            limitWatch.stop()
            recorder.cancel()
            _ = finish(.cancelled)
            return true
        case .captured:
            capturedSamples = nil
            _ = finish(.cancelled)
            return true
        case .transcribing:
            pending?.resolve(.cancelled)
            return true
        }
    }

    // Frees the model's memory, but only between dictations.
    func unloadModelIfIdle() async {
        guard phase == .idle else { return }
        preload?.cancel()
        preload = nil
        isModelReady = false
        await transcriber.unload()
    }

    private func start(invokedAt: ContinuousClock.Instant) -> DictationOutcome {
        if system.sessionMarker != nil {
            system.sessionMarker = nil
            system.endActivity()
            return report(.failed(.sessionLost))
        }
        guard system.isMicrophoneAuthorized else { return report(.failed(.microphoneNotAuthorized)) }
        guard system.isModelInstalled else { return report(.failed(.modelMissing)) }
        guard system.startActivity() else { return report(.failed(.liveActivityUnavailable)) }
        do {
            try recorder.start()
        } catch {
            system.endActivity()
            return report(.failed(.audioStartFailed))
        }
        system.sessionMarker = Date()
        phase = .listening
        limitWatch.start(onWarning: {}, onLimit: { [weak self] in self?.endCapture(.limitReached) })
        preloadModel()
        var started = metric(.started)
        started.invocationToListeningMs = milliseconds(from: invokedAt)
        system.record(started)
        return .started
    }

    private func stop(invokedAt: ContinuousClock.Instant) async -> DictationOutcome {
        limitWatch.stop()
        let backgroundRemaining = system.backgroundTimeRemaining
        let modelWasReady = isModelReady
        let samples: [Float]
        do {
            samples = try capturedSamples ?? recorder.stop()
        } catch {
            samples = []
        }
        capturedSamples = nil
        phase = .transcribing
        system.updateActivity(.transcribing)
        system.beginBackgroundTask { [weak self] in self?.pending?.resolve(.failed(.backgroundTimeExpired)) }

        let outcome: DictationOutcome
        switch SpeechCheck.assess(samples) {
        case .nothingToTranscribe:
            outcome = .nothingHeard
        case .transcribable:
            outcome = await transcribe(samples)
        }

        var stopped = metric(outcome)
        stopped.stopToResultMs = milliseconds(from: invokedAt)
        stopped.audioSeconds = Double(samples.count) / Double(SpeechCheck.sampleRate)
        stopped.backgroundSecondsRemainingAtStop = backgroundRemaining
        stopped.modelWasReadyAtStop = modelWasReady
        return finish(outcome, metric: stopped)
    }

    // Capture ends by itself on the time limit or an interruption; the audio waits for the next trigger.
    private func endCapture(_ reason: CaptureEnd) {
        guard phase == .listening else { return }
        limitWatch.stop()
        capturedSamples = (try? recorder.stop()) ?? []
        captureEnd = reason
        phase = .captured(reason)
        system.updateActivity(.captured)
    }

    private func transcribe(_ samples: [Float]) async -> DictationOutcome {
        let transcriber = self.transcriber
        let waitForTimeLimit = self.waitForTimeLimit
        let limit = Self.transcriptionTimeLimit(audioSeconds: Double(samples.count) / Double(SpeechCheck.sampleRate))
        return await withCheckedContinuation { continuation in
            let pending = PendingTranscription(continuation)
            self.pending = pending
            let timer = Task { @MainActor in
                await waitForTimeLimit(limit)
                pending.resolve(.failed(.timedOut))
            }
            Task { @MainActor in
                do {
                    let text = try await transcriber.transcribe(samples)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    pending.resolve(text.isEmpty ? .nothingHeard : .transcribed(text))
                } catch {
                    pending.resolve(.failed(.transcriptionFailed))
                }
                timer.cancel()
            }
        }
    }

    private func preloadModel() {
        guard !isModelReady, preload == nil else { return }
        let transcriber = self.transcriber
        preload = Task { @MainActor [weak self] in
            let ready = (try? await transcriber.prepare()) != nil
            guard let self, !Task.isCancelled else { return }
            self.isModelReady = ready
            self.preload = nil
        }
    }

    private func finish(_ outcome: DictationOutcome, metric: DictationMetric? = nil) -> DictationOutcome {
        pending = nil
        phase = .idle
        system.sessionMarker = nil
        system.endActivity()
        system.endBackgroundTask()
        system.record(metric ?? self.metric(outcome))
        captureEnd = nil
        return outcome
    }

    private func report(_ outcome: DictationOutcome) -> DictationOutcome {
        system.record(metric(outcome))
        return outcome
    }

    private func metric(_ outcome: DictationOutcome) -> DictationMetric {
        DictationMetric(date: Date(), outcome: outcome.kind, appWasActive: system.isAppActive, captureEnd: captureEnd?.rawValue)
    }

    private func milliseconds(from start: ContinuousClock.Instant) -> Double {
        (now() - start) / .milliseconds(1)
    }
}

// The first of transcription, time limit, cancellation and background expiry decides the outcome.
@MainActor
private final class PendingTranscription {
    private var continuation: CheckedContinuation<DictationOutcome, Never>?

    init(_ continuation: CheckedContinuation<DictationOutcome, Never>) {
        self.continuation = continuation
    }

    func resolve(_ outcome: DictationOutcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}
