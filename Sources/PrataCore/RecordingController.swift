import AppKit
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
    private let pendingLevel = OSAllocatedUnfairLock<Float?>(initialState: nil)

    public private(set) var isRecording = false
    private var isCapturingTail = false
    public var onStateChange: ((Bool) -> Void)?
    public var onLevel: ((Float) -> Void)?
    public var keepClipboardContent = true
    private var clipboardOwnership = ClipboardOwnershipTracker()

    public init(engine: TranscriptionEngine, modelName: String, tailDuration: TimeInterval = 0.15) {
        self.engine = engine
        self.modelName = modelName
        self.tailDuration = tailDuration
        setUpLevelForwarding()
    }

    private func setUpLevelForwarding() {
        let pendingLevel = self.pendingLevel
        recorder.onLevel = { [pendingLevel, weak self] level in
            let shouldSchedule = pendingLevel.withLock { state -> Bool in
                let wasEmpty = state == nil
                state = level
                return wasEmpty
            }
            guard shouldSchedule else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                let level = pendingLevel.withLock { state -> Float? in
                    defer { state = nil }
                    return state
                }
                if let level {
                    self.onLevel?(level)
                }
            }
        }
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

    @discardableResult
    public func startRecording() -> Bool {
        guard !isRecording, !isCapturingTail else { return false }
        do {
            try recorder.start()
            isRecording = true
            onStateChange?(true)
            return true
        } catch {
            logger.error("failed to start recording: \(String(describing: error), privacy: .public)")
            return false
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
                let keepClipboardContent = self.keepClipboardContent
                let generation: Int? = keepClipboardContent
                    ? self.clipboardOwnership.begin { PasteService.snapshot() }.generation
                    : nil
                if !keepClipboardContent {
                    self.clipboardOwnership.cancel()
                }
                let changeCountAfterWrite = PasteService.writeToPasteboard(text)
                PasteService.paste()
                let pasted = AXIsProcessTrusted()
                self.logger.info("\(modelName, privacy: .public): \(Self.format(audioSeconds), privacy: .public) audio -> pasted in \(Self.format(Date().timeIntervalSince(released)), privacy: .public) pasted=\(pasted, privacy: .public): \(text, privacy: .private)")

                if let generation {
                    if !pasted {
                        self.clipboardOwnership.cancel()
                        self.logger.info("clipboard kept (not pasted)")
                    } else {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        switch self.clipboardOwnership.finish(generation: generation) {
                        case .skip:
                            self.logger.info("clipboard kept (superseded)")
                        case .evaluate(let original):
                            let currentChangeCount = NSPasteboard.general.changeCount
                            if PasteService.shouldRestoreClipboard(
                                keepSetting: keepClipboardContent,
                                pasteDelivered: pasted,
                                changeCountAfterWrite: changeCountAfterWrite,
                                currentChangeCount: currentChangeCount
                            ) {
                                PasteService.restore(original)
                                self.logger.info("clipboard restored")
                            } else {
                                self.logger.info("clipboard kept (clipboard changed)")
                            }
                        }
                    }
                }
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
