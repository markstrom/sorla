import AVFoundation
import UIKit

// The audio session is active only between start and stop, so background audio covers recording and nothing else.
@MainActor
final class LiveDictationRecorder: DictationRecorder {
    var onCaptureEnded: ((CaptureEnd) -> Void)?
    var onDiagnostic: ((String) -> Void)?

    // Starting over on a fresh engine is for a dead input, not a loop: a few times per recording at most.
    static let maximumRestarts = 3

    private let session: DictationAudioSession
    private let input: DictationAudioInput
    private let meter = InputMeter()
    private let center: NotificationCenter
    private let now: () -> ContinuousClock.Instant
    private let onMain: (@escaping @MainActor () -> Void) -> Void
    private var recorder: AudioRecorder!
    private var observers: [NSObjectProtocol] = []
    private var isCapturing = false
    private var startedAt: ContinuousClock.Instant?
    private var restarts = 0

    init(
        session: DictationAudioSession = SystemDictationAudioSession(),
        input: DictationAudioInput = FreshEngineAudioInput(),
        resample: @escaping ([Float], Double) throws -> [Float] = { try AudioRecorder.resample($0, sampleRate: $1) },
        center: NotificationCenter = .default,
        now: @escaping () -> ContinuousClock.Instant = { .now },
        // The meter reports from the audio thread; the default hops to the main actor.
        onMain: @escaping (@escaping @MainActor () -> Void) -> Void = { job in
            DispatchQueue.main.async { MainActor.assumeIsolated(job) }
        }
    ) {
        self.session = session
        self.input = input
        self.center = center
        self.now = now
        self.onMain = onMain
        let metered = MeteredAudioInput(input, meter: meter) { [weak self] in
            onMain { self?.restartSilentStart() }
        }
        recorder = AudioRecorder(input: metered, resample: resample)
    }

    // Category and mode are set before activation, and the engine is made only once the session is active.
    func start() throws {
        do {
            try session.configure(.dictation)
            try session.activate()
        } catch {
            diagnoseSession()
            session.deactivate()
            throw error
        }
        restarts = 0
        do {
            try recorder.start()
        } catch {
            diagnoseSession()
            session.deactivate()
            throw error
        }
        diagnoseSession()
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

    private func endCapturing() {
        isCapturing = false
        startedAt = nil
        stopObserving()
    }

    private func diagnoseSession() {
        onDiagnostic?("session: \(session.snapshot().summary)")
    }

    // The first second came in silent: whatever the reason, a new engine is the one thing that can fix it.
    // If it stays silent, the coordinator reports `failed.silentInput` at stop.
    private func restartSilentStart() {
        // Checked again here: by the time this runs the recording may have ended or been started over.
        guard isCapturing, meter.seconds >= 1, meter.peak < SpeechCheck.silentInputPeak else { return }
        startOver(reason: "first second silent")
    }

    // Drops what was captured (nothing but silence) and starts again on a new engine.
    private func startOver(reason: String) {
        guard restarts < Self.maximumRestarts else { return }
        restarts += 1
        recorder.cancel()
        do {
            try recorder.start()
            onDiagnostic?("audioRestart: \(reason), started over on a new engine")
        } catch {
            onDiagnostic?("audioRestart: \(reason), new engine failed: \(error)")
            captureEnded(.routeChanged)
        }
    }

    // The engine stops itself when its configuration changes (route or format). Nothing heard yet: start over.
    // Otherwise carry on at the same rate on a new engine, or end capture and keep what was heard.
    private func engineConfigurationChanged() {
        guard isCapturing else { return }
        if meter.peak < SpeechCheck.silentInputPeak {
            startOver(reason: "configuration change")
        } else if restarts < Self.maximumRestarts, input.restart() {
            restarts += 1
            onDiagnostic?("audioRestart: configuration change, continued on a new engine")
        } else {
            onDiagnostic?("audioRestart: configuration change, input could not continue")
            captureEnded(.routeChanged)
        }
    }

    // An input that only appeared after activation (a route that was still empty) means the engine may have
    // opened no microphone at all; if nothing has been heard yet, start over on the new route.
    private func routeChanged(_ note: Notification) {
        guard isCapturing,
              let previous = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
              previous.inputs.isEmpty,
              session.snapshot().inputPort != nil,
              meter.peak < SpeechCheck.silentInputPeak
        else { return }
        startOver(reason: "input route appeared")
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

    // A call or Siri, or a media-services reset, ends capture; what was heard so far is kept for the next
    // trigger, and the next start builds a new session setup and engine.
    private func observe() {
        stopObserving()
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began
                else { return }
                MainActor.assumeIsolated { self?.captureEnded(.interrupted) }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onDiagnostic?("audioRestart: media services were reset")
                    self?.captureEnded(.interrupted)
                }
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.engineConfigurationChanged() }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.routeChanged(note) }
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
