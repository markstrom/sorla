import AVFoundation

// The audio session is active only between start and stop, so background audio covers recording and nothing else.
@MainActor
final class LiveDictationRecorder: DictationRecorder {
    var onCaptureEnded: ((CaptureEnd) -> Void)?
    var onDiagnostic: ((String) -> Void)?

    private let session: DictationAudioSession
    private let recorder: AudioRecorder
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(
        session: DictationAudioSession = SystemDictationAudioSession(),
        input: AudioInput = EngineAudioInput(),
        resample: @escaping ([Float], Double) throws -> [Float] = { try AudioRecorder.resample($0, sampleRate: $1) },
        center: NotificationCenter = .default
    ) {
        self.session = session
        self.center = center
        recorder = AudioRecorder(input: input, resample: resample)
    }

    // Category and mode are set before activation.
    func start() throws {
        do {
            try session.configure(.dictation)
            try session.activate()
        } catch {
            diagnoseSession()
            session.deactivate()
            throw error
        }
        do {
            try recorder.start()
        } catch {
            diagnoseSession()
            session.deactivate()
            throw error
        }
        diagnoseSession()
        observe()
    }

    func stop() throws -> [Float] {
        stopObserving()
        defer { session.deactivate() }
        return try recorder.stop()
    }

    func cancel() {
        stopObserving()
        recorder.cancel()
        session.deactivate()
    }

    private func diagnoseSession() {
        onDiagnostic?("session: \(session.snapshot().summary)")
    }

    // A call, Siri or a lost route ends capture; what was heard so far is kept for the next trigger.
    private func observe() {
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began
                else { return }
                MainActor.assumeIsolated { self?.onCaptureEnded?(.interrupted) }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onCaptureEnded?(.interrupted) }
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onCaptureEnded?(.routeChanged) }
            },
        ]
    }

    private func stopObserving() {
        observers.forEach(center.removeObserver)
        observers = []
    }
}
