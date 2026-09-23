import AppKit
import ApplicationServices
import Foundation
import os

@MainActor
public final class RecordingController {
    private let recorder = AudioRecorder()
    private let engine: TranscriptionEngine
    private let modelName: String
    public let tailDuration: TimeInterval
    private let logger = Logger(subsystem: "com.prata.app", category: "RecordingController")

    public private(set) var isRecording = false
    private var isCapturingTail = false
    public var onStateChange: ((Bool) -> Void)?
    public var onSpectrum: ((SIMD8<Float>) -> Void)?
    public var onPhaseChange: ((DictationPhase) -> Void)?
    public var phase: DictationPhase { phaseTracker.phase }
    private var phaseTracker = DictationPhaseTracker()
    private var recordingID = 0
    public var keepClipboardContent = true
    private var clipboardOwnership = ClipboardOwnershipTracker()

    public private(set) var isModelReady = false
    public var onModelReadyChange: ((Bool) -> Void)?

    public private(set) var lastTranscript: String?
    private var isPasteLastInFlight = false

    public init(engine: TranscriptionEngine, modelName: String, tailDuration: TimeInterval = 0.15) {
        self.engine = engine
        self.modelName = modelName
        self.tailDuration = tailDuration
        setUpForwarding()
    }

    private func setUpForwarding() {
        recorder.onSpectrum = Self.latestValueForwarder { [weak self] bands in self?.onSpectrum?(bands) }
    }

    // Keeps only the newest value so a busy main actor gets one hop per burst, not one per buffer.
    private static func latestValueForwarder<Value: Sendable>(
        _ deliver: @escaping @Sendable @MainActor (Value) -> Void
    ) -> @Sendable (Value) -> Void {
        let pending = OSAllocatedUnfairLock<Value?>(initialState: nil)
        return { value in
            let shouldSchedule = pending.withLock { state -> Bool in
                defer { state = value }
                return state == nil
            }
            guard shouldSchedule else { return }

            Task { @MainActor in
                let latest = pending.withLock { state -> Value? in
                    defer { state = nil }
                    return state
                }
                if let latest {
                    deliver(latest)
                }
            }
        }
    }

    public func prepare() {
        let engine = self.engine
        let modelName = self.modelName
        isModelReady = false
        onModelReadyChange?(false)
        Task {
            let start = Date()
            do {
                try await engine.prepare()
                self.logger.info("model ready: \(modelName, privacy: .public) in \(Self.format(Date().timeIntervalSince(start)), privacy: .public)")
                self.isModelReady = true
                self.onModelReadyChange?(true)
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
            recordingID = phaseTracker.beginRecording()
            onStateChange?(true)
            onPhaseChange?(.recording)
            return true
        } catch {
            logger.error("failed to start recording: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    @discardableResult
    public func stopRecordingAndTranscribe() -> Bool {
        guard isRecording else { return false }
        isRecording = false
        isCapturingTail = true
        onStateChange?(false)
        let dictationID = recordingID
        updatePhase { $0.release(dictationID) }

        let released = Date()
        let frontmostPIDAtRelease = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let tailDuration = self.tailDuration
        let engine = self.engine
        let modelName = self.modelName

        Task { @MainActor in
            defer { self.updatePhase { $0.finish(dictationID) } }
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
                self.lastTranscript = text

                let frontmostPIDAtDelivery = NSWorkspace.shared.frontmostApplication?.processIdentifier
                guard PasteService.shouldAutoPaste(
                    frontmostPIDAtRelease: frontmostPIDAtRelease,
                    frontmostPIDAtDelivery: frontmostPIDAtDelivery
                ) else {
                    self.clipboardOwnership.cancel()
                    PasteService.writeToPasteboard(text)
                    self.logger.info("paste skipped (frontmost app changed)")
                    return
                }

                let outcome = self.issuePaste(text)
                self.updatePhase { $0.finish(dictationID) }
                self.logger.info("\(modelName, privacy: .public): \(Self.format(audioSeconds), privacy: .public) audio -> pasted in \(Self.format(Date().timeIntervalSince(released)), privacy: .public) pasted=\(outcome.pasted, privacy: .public): \(text, privacy: .private)")
                await self.settleClipboard(outcome)
            } catch {
                self.logger.error("\(modelName, privacy: .public): transcription failed: \(String(describing: error), privacy: .public)")
            }
        }
        return true
    }

    // Pastes the most recent successful transcript at the current cursor, same path as a dictation.
    public func pasteLastTranscript(after prepare: @escaping @MainActor () async -> Bool = { true }) {
        guard PasteService.shouldPasteLast(
            hasTranscript: lastTranscript != nil,
            phase: phase,
            isPasteLastInFlight: isPasteLastInFlight
        ), let text = lastTranscript else {
            logger.info("paste-last skipped (no transcript, or a dictation or paste-last in progress)")
            return
        }
        isPasteLastInFlight = true
        Task { @MainActor in
            defer { self.isPasteLastInFlight = false }
            guard await prepare() else {
                self.logger.info("paste-last skipped (target app never became frontmost)")
                return
            }
            guard self.phase == .idle else {
                self.logger.info("paste-last skipped (dictation started)")
                return
            }
            let outcome = self.issuePaste(text)
            self.logger.info("paste-last: pasted=\(outcome.pasted, privacy: .public)")
            await self.settleClipboard(outcome)
        }
    }

    private struct PasteOutcome {
        let pasted: Bool
        let generation: Int?
        let changeCountAfterWrite: Int
        let keepClipboardContent: Bool
    }

    // Writes the text to the pasteboard, posts the tagged ⌘V, and reports whether it was likely delivered.
    private func issuePaste(_ text: String) -> PasteOutcome {
        let keepClipboardContent = self.keepClipboardContent
        let generation: Int? = keepClipboardContent
            ? clipboardOwnership.begin { PasteService.snapshot() }.generation
            : nil
        if !keepClipboardContent {
            clipboardOwnership.cancel()
        }
        let changeCountAfterWrite = PasteService.writeToPasteboard(text, transient: keepClipboardContent)
        PasteService.paste()
        let pasted = AXIsProcessTrusted()
        return PasteOutcome(pasted: pasted, generation: generation, changeCountAfterWrite: changeCountAfterWrite, keepClipboardContent: keepClipboardContent)
    }

    // Restores the user's original clipboard once the paste has had time to land, unless it was superseded or changed.
    private func settleClipboard(_ outcome: PasteOutcome) async {
        guard let generation = outcome.generation else { return }
        guard outcome.pasted else {
            clipboardOwnership.cancel()
            logger.info("clipboard kept (not pasted)")
            return
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        switch clipboardOwnership.finish(generation: generation) {
        case .skip:
            logger.info("clipboard kept (superseded)")
        case .evaluate(let original):
            let currentChangeCount = NSPasteboard.general.changeCount
            if PasteService.shouldRestoreClipboard(
                keepSetting: outcome.keepClipboardContent,
                pasteDelivered: outcome.pasted,
                changeCountAfterWrite: outcome.changeCountAfterWrite,
                currentChangeCount: currentChangeCount
            ) {
                PasteService.restore(original)
                logger.info("clipboard restored")
            } else {
                logger.info("clipboard kept (clipboard changed)")
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
        let dictationID = recordingID
        updatePhase { $0.cancel(dictationID) }
        logger.info("recording cancelled")
    }

    private func updatePhase(_ transition: (inout DictationPhaseTracker) -> Bool) {
        if transition(&phaseTracker) {
            onPhaseChange?(phaseTracker.phase)
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        String(format: "%.2fs", seconds)
    }
}
