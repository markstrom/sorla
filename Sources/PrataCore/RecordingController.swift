import Foundation

@MainActor
public final class RecordingController {
    private let recorder = AudioRecorder()
    private let engine: TranscriptionEngine

    public private(set) var isRecording = false
    public var onStateChange: ((Bool) -> Void)?

    public init(engine: TranscriptionEngine = ParakeetTranscriptionEngine()) {
        self.engine = engine
    }

    public func prepare() {
        Task {
            let start = Date()
            do {
                try await engine.prepare()
                print("Prata: model ready in \(Self.format(Date().timeIntervalSince(start)))")
            } catch {
                print("Prata: model preparation failed: \(error)")
            }
        }
    }

    public func startRecording() {
        guard !isRecording else { return }
        do {
            try recorder.start()
            isRecording = true
            onStateChange?(true)
        } catch {
            print("Prata: failed to start recording: \(error)")
        }
    }

    public func stopRecordingAndTranscribe() {
        guard isRecording else { return }
        isRecording = false
        onStateChange?(false)

        let released = Date()
        let samples: [Float]
        do {
            samples = try recorder.stop()
        } catch {
            print("Prata: failed to stop recording: \(error)")
            return
        }
        guard !samples.isEmpty else {
            print("Prata: no audio captured")
            return
        }

        Task {
            do {
                let text = try await engine.transcribe(samples)
                guard !text.isEmpty else {
                    print("Prata: empty transcription")
                    return
                }
                PasteService.writeToPasteboard(text)
                PasteService.paste()
                let audioSeconds = Double(samples.count) / 16_000
                print("Prata: \(Self.format(audioSeconds)) audio -> pasted in \(Self.format(Date().timeIntervalSince(released))): \"\(text)\"")
            } catch {
                print("Prata: transcription failed: \(error)")
            }
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        String(format: "%.2fs", seconds)
    }
}
