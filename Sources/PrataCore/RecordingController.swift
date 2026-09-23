import ApplicationServices
import Foundation
import os

@MainActor
public final class RecordingController {
    private let recorder = AudioRecorder()
    private var engine: TranscriptionEngine
    private var modelName: String
    private let tailDuration: TimeInterval
    private let logger = Logger(subsystem: "com.prata.app", category: "RecordingController")

    public private(set) var isRecording = false
    private var isCapturingTail = false
    public var onStateChange: ((Bool) -> Void)?

    public init(engine: TranscriptionEngine, modelName: String, tailDuration: TimeInterval = 0.15) {
        self.engine = engine
        self.modelName = modelName
        self.tailDuration = tailDuration
    }

    public func setEngine(_ engine: TranscriptionEngine, name: String) {
        self.engine = engine
        self.modelName = name
        prepare()
    }

    public func prepare() {
        let engine = self.engine
        let modelName = self.modelName
        Task {
            let start = Date()
            do {
                try await engine.prepare()
                self.logger.info("model ready: \(modelName, privacy: .public) in \(Self.format(Date().timeIntervalSince(start)), privacy: .public)")
            } catch {
                self.logger.error("model preparation failed: \(modelName, privacy: .public): \(String(describing: error), privacy: .public)")
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
        let engine = self.engine
        let modelName = self.modelName

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

            let audioSeconds = Double(samples.count) / 16_000
            let peakAmplitude = samples.reduce(into: Float(0)) { peak, sample in peak = max(peak, abs(sample)) }

            do {
                let text = try await engine.transcribe(samples)
                guard !text.isEmpty else {
                    self.logger.info("\(modelName, privacy: .public): empty transcription: \(Self.format(audioSeconds), privacy: .public) audio, peak=\(peakAmplitude, privacy: .public)")
                    return
                }
                PasteService.writeToPasteboard(text)
                PasteService.paste()
                let pasted = AXIsProcessTrusted()
                self.logger.info("\(modelName, privacy: .public): \(Self.format(audioSeconds), privacy: .public) audio -> pasted in \(Self.format(Date().timeIntervalSince(released)), privacy: .public) pasted=\(pasted, privacy: .public): \(text, privacy: .private)")
            } catch {
                self.logger.error("\(modelName, privacy: .public): transcription failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func cancelRecording() {
        guard isRecording else { return }
        do {
            _ = try recorder.stop()
        } catch {
            logger.error("failed to stop recording: \(String(describing: error), privacy: .public)")
        }
        isRecording = false
        onStateChange?(false)
        logger.info("recording cancelled")
    }

    private static func format(_ seconds: TimeInterval) -> String {
        String(format: "%.2fs", seconds)
    }
}
