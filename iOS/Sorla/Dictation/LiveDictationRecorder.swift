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

    private let session: DictationAudioSession
    private let input: DictationAudioInput
    private let meter = InputMeter()
    private let center: NotificationCenter
    private let now: () -> ContinuousClock.Instant
    private let isInForeground: @MainActor () -> Bool
    private var recorder: AudioRecorder!
    private var observers: [NSObjectProtocol] = []
    private var mediaResetObserver: NSObjectProtocol?
    private var isCapturing = false
    private var startedAt: ContinuousClock.Instant?
    private var resumes = 0
    private var restartedSilentStart = false

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
        }
    ) {
        self.session = session
        self.input = input
        self.center = center
        self.now = now
        self.isInForeground = isInForeground
        let metered = MeteredAudioInput(input, meter: meter) { [weak self] in
            onMain { self?.silentStart() }
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
        restartedSilentStart = false
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
        return try recorder.stop()
    }

    func cancel() {
        endCapturing()
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
        stopObserving()
    }

    private func diagnoseSession() {
        onDiagnostic?("session: \(session.snapshot().summary)")
    }

    private func diagnoseEngine() {
        onDiagnostic?("engine: \(input.preparation)")
    }

    // The whole first second was below -90 dBFS. On the first device run the first recording after launch did this
    // and the next recording, with the session activated again and the engine started again, captured speech. So
    // once, in the foreground, do exactly what the next recording would: drop the silence, deactivate, set the
    // session up again and restart the engine. If it stays silent, the coordinator reports `failed.silentInput`.
    private func silentStart() {
        // Checked again here: by the time this runs the recording may have ended or been started over.
        guard isCapturing, meter.seconds >= 1, meter.peak < SpeechCheck.silentInputPeak else { return }
        guard !restartedSilentStart else {
            onDiagnostic?("audioRestart: first second silent again, not restarted")
            return
        }
        restartedSilentStart = true
        guard isInForeground() else {
            // A non-mixable session can't be activated, nor audio input started, from the background.
            onDiagnostic?("audioRestart: first second silent, in the background, not restarted")
            return
        }
        recorder.cancel()
        session.deactivate()
        do {
            try activateSession()
            try recorder.start()
            onDiagnostic?("audioRestart: first second silent, restarted session and engine (\(input.preparation))")
        } catch {
            onDiagnostic?("audioRestart: first second silent, restart failed: \(error)")
            captureEnded(.interrupted)
        }
    }

    // The engine stops itself when its configuration changes (route or format). Carry on at the same rate on the
    // same engine. At another rate: if nothing has been heard yet, start over at the new rate; otherwise end capture
    // and keep what was heard, since audio at two rates can't be joined.
    private func engineConfigurationChanged() {
        guard isCapturing else { return }
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
