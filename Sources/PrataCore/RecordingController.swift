import ApplicationServices
import Foundation
import os

@MainActor
public final class RecordingController {
    private let recorder = AudioRecorder()
    private let engine: TranscriptionEngine
    private let tailDuration: TimeInterval
    private let logger = Logger(subsystem: "com.prata.app", category: "RecordingController")

    public private(set) var isRecording = false
    private var isCapturingTail = false
    public var onStateChange: ((Bool) -> Void)?

    public init(engine: TranscriptionEngine, tailDuration: TimeInterval = 0.15) {
        self.engine = engine
        self.tailDuration = tailDuration
    }

    public func prepare() {
        Task {
            let start = Date()
            do {
                try await engine.prepare()
                logger.info("model ready in \(Self.format(Date().timeIntervalSince(start)), privacy: .public)")
            } catch {
                logger.error("model preparation failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func startRecording() {
        guard !isRecording, !isCapturingTail else { return }
        do {
            try recorder.start()
            isRecording = true
            onStateChange?(true)
        } catch {
            logger.error("failed to start recording: \(String(describing: error), privacy: .public)")
        }
    }

    public func stopRecordingAndTranscribe() {
        guard isRecording else { return }
        isRecording = false
        isCapturingTail = true
        onStateChange?(false)

        let released = Date()
        let tailDuration = self.tailDuration

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(tailDuration * 1_000_000_000))
            self.isCapturingTail = false

            let samples: [Float]
            do {
                samples = try self.recorder.stop()
            } catch {
                self.logger.error("failed to stop recording: \(String(describing: error), privacy: .public)")
                return
            }
            guard !samples.isEmpty else {
                self.logger.info("no audio captured")
                return
            }

            do {
                let text = try await self.engine.transcribe(samples)
                guard !text.isEmpty else {
                    self.logger.info("empty transcription")
                    return
                }
                PasteService.writeToPasteboard(text)
                PasteService.paste()
                let pasted = AXIsProcessTrusted()
                let audioSeconds = Double(samples.count) / 16_000
                self.logger.info("\(Self.format(audioSeconds), privacy: .public) audio -> pasted in \(Self.format(Date().timeIntervalSince(released)), privacy: .public) pasted=\(pasted, privacy: .public): \(text, privacy: .private)")
            } catch {
                self.logger.error("transcription failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        String(format: "%.2fs", seconds)
    }
}
