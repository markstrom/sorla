import AVFoundation

// The audio session is active only between start and stop, so background audio covers recording and nothing else.
@MainActor
final class LiveDictationRecorder: DictationRecorder {
    var onCaptureEnded: ((CaptureEnd) -> Void)?

    private let recorder = AudioRecorder()
    private var observers: [NSObjectProtocol] = []

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [.allowBluetoothHFP])
        try session.setActive(true)
        do {
            try recorder.start()
        } catch {
            deactivate()
            throw error
        }
        observe()
    }

    func stop() throws -> [Float] {
        stopObserving()
        defer { deactivate() }
        return try recorder.stop()
    }

    func cancel() {
        stopObserving()
        recorder.cancel()
        deactivate()
    }

    private func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // A call, Siri or a lost route ends capture; what was heard so far is kept for the next trigger.
    private func observe() {
        let center = NotificationCenter.default
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
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}
