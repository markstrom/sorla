import AVFoundation
import UIKit

// The audio session is active only between start and stop, so background audio covers recording and nothing else.
// A recording starts in the foreground (the intent brings Sorla forward first) and may go on in the background.
@MainActor
final class LiveDictationRecorder: DictationRecorder {
    var onCaptureEnded: ((CaptureEnd) -> Void)?
    var onDiagnostic: ((String) -> Void)?

    // Carrying on after configuration changes is for a route that changed, not a loop: a few times per recording.
    static let maximumResumes = 3

    // A start that stays all zeros is started over on a new engine, a few times, each after a longer pause with the
    // session inactive, so iOS has time to finish bringing Sorla forward. On the device one restart right away
    // recovered the input once and failed once. With the silence windows below, the last restart comes about
    // 3.5 s after the start (plus the session activations).
    static let silentRestartDelays: [Duration] = [.milliseconds(200), .milliseconds(400), .milliseconds(600)]
    static var maximumSilentRestarts: Int { silentRestartDelays.count }
    // How long an input has to be all zeros to count as dead: the first second, as before, then half a second on a
    // restarted input (a live microphone has sound from its first buffer: 0.0 s on every recovered device run).
    static let firstSilenceWindow: Double = 1
    static let restartSilenceWindow: Double = 0.5

    private let session: DictationAudioSession
    private let input: DictationAudioInput
    private let meter = InputMeter()
    private let center: NotificationCenter
    private let now: () -> ContinuousClock.Instant
    private let isInForeground: @MainActor () -> Bool
    private let after: (Duration, @escaping @MainActor () -> Void) -> Void
    private var recorder: AudioRecorder!
    private var observers: [NSObjectProtocol] = []
    private var mediaResetObserver: NSObjectProtocol?
    private var isCapturing = false
    private var startedAt: ContinuousClock.Instant?
    private var resumes = 0
    private var silentRestarts = 0
    // Set while the input is stopped between a silent start and its restart.
    private var pendingRestart: Int?
    private var restartTokens = 0
    // The all-zero audio dropped by restarts, at 16 kHz. It is handed back if nothing but silence ever arrives, so a
    // dead input still ends as `failed.silentInput` and never passes for a short or empty recording.
    private var droppedSilence = 0

    init(
        session: DictationAudioSession = SystemDictationAudioSession(),
        input: DictationAudioInput = SharedEngineAudioInput(),
        resample: @escaping ([Float], Double) throws -> [Float] = { try AudioRecorder.resample($0, sampleRate: $1) },
        center: NotificationCenter = .default,
        now: @escaping () -> ContinuousClock.Instant = { .now },
        isInForeground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState != .background },
        // The meter reports from the audio thread; the default hops to the main actor.
        onMain: @escaping (@escaping @MainActor () -> Void) -> Void = { job in
            DispatchQueue.main.async { MainActor.assumeIsolated(job) }
        },
        // Runs a job on the main actor after a delay; tests run it when they choose.
        after: @escaping (Duration, @escaping @MainActor () -> Void) -> Void = { delay, job in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay / .seconds(1)) { MainActor.assumeIsolated(job) }
        }
    ) {
        self.session = session
        self.input = input
        self.center = center
        self.now = now
        self.isInForeground = isInForeground
        self.after = after
        let metered = MeteredAudioInput(input, meter: meter) { [weak self] event in
            onMain { self?.meterReported(event) }
        }
        recorder = AudioRecorder(input: metered, resample: resample)
        // The engine doesn't survive a media-services reset, recording or not.
        mediaResetObserver = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.mediaServicesWereReset() }
        }
    }

    // Category and mode are set before activation, and the engine is made (the first time) only once the session is
    // active, so its input is read from a session that allows input.
    func start() throws {
        do {
            try activateSession()
        } catch {
            diagnoseSession()
            session.deactivate()
            throw error
        }
        resumes = 0
        silentRestarts = 0
        droppedSilence = 0
        meter.silenceWindow = Self.firstSilenceWindow
        do {
            try recorder.start()
        } catch {
            diagnoseSession()
            diagnoseEngine()
            session.deactivate()
            throw error
        }
        diagnoseSession()
        diagnoseEngine()
        isCapturing = true
        startedAt = now()
        observe()
    }

    func stop() throws -> [Float] {
        endCapturing()
        defer { session.deactivate() }
        let samples = try recorder.stop()
        let dropped = droppedSilence
        droppedSilence = 0
        guard dropped > 0, !Self.hasSound(samples) else { return samples }
        return [Float](repeating: 0, count: dropped) + samples
    }

    func cancel() {
        endCapturing()
        droppedSilence = 0
        recorder.cancel()
        session.deactivate()
    }

    private func activateSession() throws {
        try session.configure(.dictation)
        try session.activate()
    }

    private func endCapturing() {
        isCapturing = false
        startedAt = nil
        pendingRestart = nil
        stopObserving()
    }

    private func diagnoseSession() {
        onDiagnostic?("session: \(session.snapshot().summary)")
    }

    private func diagnoseEngine() {
        onDiagnostic?("engine: \(input.preparation)")
    }

    private func meterReported(_ event: InputMeter.Event) {
        switch event {
        case .silentStart: silentStart()
        case .firstSound: firstSound()
        }
    }

    // The input started all zeros (below -90 dBFS for the whole silence window). It has only been seen right after
    // the intent brought Sorla forward, never on a plain launch, and a new engine right away recovered it once and
    // failed once. So, in the foreground, up to `maximumSilentRestarts` times: drop the silence, stop the engine,
    // deactivate, wait a little longer each time, then set the session up again and start a new engine. Audio
    // that arrives on any attempt is kept. If it stays silent, the coordinator reports `failed.silentInput`.
    private func silentStart() {
        // Checked again here: by the time this runs the recording may have ended or been started over.
        guard isCapturing, pendingRestart == nil, meter.isSilentStart else { return }
        let silentFor = String(format: "%.1f", meter.seconds)
        guard silentRestarts < Self.maximumSilentRestarts else {
            onDiagnostic?("audioRestart: silent for \(silentFor) s after restart \(silentRestarts), \(elapsed()) ms after the start, not restarted again")
            return
        }
        guard isInForeground() else {
            // A non-mixable session can't be activated, nor audio input started, from the background.
            onDiagnostic?("audioRestart: silent for \(silentFor) s, in the background, not restarted")
            return
        }
        silentRestarts += 1
        let attempt = silentRestarts
        let delay = Self.silentRestartDelays[attempt - 1]
        droppedSilence += Int((meter.seconds * Double(SpeechCheck.sampleRate)).rounded())
        recorder.cancel()
        input.discardEngine()
        session.deactivate()
        restartTokens += 1
        let token = restartTokens
        pendingRestart = token
        onDiagnostic?("audioRestart: silent for \(silentFor) s, \(elapsed()) ms after the start, restart \(attempt) of \(Self.maximumSilentRestarts) in \(Int(delay / .milliseconds(1))) ms")
        after(delay) { [weak self] in self?.restartAfterSilence(token: token, attempt: attempt) }
    }

    private func restartAfterSilence(token: Int, attempt: Int) {
        // A stop, cancel or ended capture during the pause leaves nothing to restart.
        guard isCapturing, pendingRestart == token else { return }
        pendingRestart = nil
        guard isInForeground() else {
            onDiagnostic?("audioRestart: in the background before restart \(attempt), capture ended")
            captureEnded(.interrupted)
            return
        }
        meter.silenceWindow = Self.restartSilenceWindow
        do {
            try activateSession()
            try recorder.start()
            diagnoseSession()
            onDiagnostic?("audioRestart: restart \(attempt), session and a new engine started \(elapsed()) ms after the start (\(input.preparation))")
        } catch {
            diagnoseSession()
            onDiagnostic?("audioRestart: restart \(attempt) failed: \(error)")
            captureEnded(.interrupted)
        }
    }

    // After a restart, when the input came back: the time tells how long the input takes to recover.
    private func firstSound() {
        guard isCapturing, pendingRestart == nil, silentRestarts > 0, meter.peak >= SpeechCheck.silentInputPeak else { return }
        onDiagnostic?("audioRestart: sound after restart \(silentRestarts), \(elapsed()) ms after the start")
    }

    private func elapsed() -> Int {
        guard let startedAt else { return 0 }
        return Int(((now() - startedAt) / .milliseconds(1)).rounded())
    }

    private static func hasSound(_ samples: [Float]) -> Bool {
        samples.contains { abs($0) >= SpeechCheck.silentInputPeak }
    }

    // The engine stops itself when its configuration changes (route or format). Carry on at the same rate on the
    // same engine. At another rate: if nothing has been heard yet, start over at the new rate; otherwise end capture
    // and keep what was heard, since audio at two rates can't be joined.
    private func engineConfigurationChanged() {
        // Between a silent start and its restart there is no engine running to carry on.
        guard isCapturing, pendingRestart == nil else { return }
        guard resumes < Self.maximumResumes else {
            onDiagnostic?("audioRestart: configuration change, too many already, capture ended")
            captureEnded(.routeChanged)
            return
        }
        resumes += 1
        switch input.resume() {
        case .continued:
            onDiagnostic?("audioRestart: configuration change, continued (\(input.preparation))")
        case .rateChanged where meter.peak < SpeechCheck.silentInputPeak:
            droppedSilence += Int((meter.seconds * Double(SpeechCheck.sampleRate)).rounded())
            recorder.cancel()
            do {
                try recorder.start()
                onDiagnostic?("audioRestart: configuration change, new rate, nothing heard yet, started over (\(input.preparation))")
            } catch {
                onDiagnostic?("audioRestart: configuration change, new rate, start failed: \(error)")
                captureEnded(.routeChanged)
            }
        case .rateChanged:
            onDiagnostic?("audioRestart: configuration change, new rate, capture ended (\(input.preparation))")
            captureEnded(.routeChanged)
        case .failed(let reason):
            onDiagnostic?("audioRestart: configuration change, input could not continue: \(reason)")
            captureEnded(.routeChanged)
        }
    }

    // A call or Siri ends capture; what was heard so far is kept for the next trigger.
    private func interrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began
        else { return }
        captureEnded(.interrupted)
    }

    // The engine is gone with the media services; the next start makes a new one and sets the session up again.
    private func mediaServicesWereReset() {
        input.discardEngine()
        guard isCapturing else { return }
        onDiagnostic?("audioRestart: media services were reset, capture ended")
        captureEnded(.interrupted)
    }

    private func enteredBackground() {
        guard isCapturing, let startedAt else { return }
        let listened = (now() - startedAt) / .seconds(1)
        let peak = meter.peak
        let level = peak > 0 ? String(format: "%.1f dBFS", 20 * log10(peak)) : "-inf dBFS"
        onDiagnostic?("background: after \(String(format: "%.1f", listened)) s listening, peak so far \(level)")
    }

    private func captureEnded(_ reason: CaptureEnd) {
        guard isCapturing else { return }
        onCaptureEnded?(reason)
    }

    private func observe() {
        stopObserving()
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.interrupted(note) }
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.engineConfigurationChanged() }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enteredBackground() }
            },
        ]
    }

    private func stopObserving() {
        observers.forEach(center.removeObserver)
        observers = []
    }
}
