import AppKit
import ApplicationServices
import Foundation
import os

@MainActor
public final class RecordingController {
    private let recorder = AudioRecorder()
    private let engine: TranscriptionEngine
    private let inputDeviceState: InputDeviceStateReading
    private let modelName: String
    public let tailDuration: TimeInterval
    private let logger = Logger(subsystem: "com.sorla.app", category: "RecordingController")

    public private(set) var isRecording = false
    private var isCapturingTail = false
    public var onStateChange: ((Bool) -> Void)?
    public var onSpectrum: ((SIMD8<Float>) -> Void)?
    public var onPhaseChange: ((DictationPhase) -> Void)?
    public var onCue: ((DictationCue) -> Void)?
    public var onMicrophoneMutedChange: ((Bool) -> Void)?
    public var onPaste: (() -> Void)?
    private var muteDetector: MicrophoneMuteDetector?
    private var deviceSeemedMuted = false
    public var phase: DictationPhase { phaseTracker.phase }
    private var phaseTracker = DictationPhaseTracker()
    private var recordingID = 0
    public var keepClipboardContent = true
    private var clipboardOwnership = ClipboardOwnershipTracker()

    public private(set) var isModelReady = false
    public var onModelReadyChange: ((Bool) -> Void)?
    public var onIssue: ((SorlaIssue) -> Void)?

    public private(set) var lastTranscript: String?
    private var isPasteLastInFlight = false

    public init(
        engine: TranscriptionEngine,
        modelName: String,
        tailDuration: TimeInterval = 0.15,
        inputDeviceState: InputDeviceStateReading = CoreAudioInputDeviceState()
    ) {
        self.engine = engine
        self.inputDeviceState = inputDeviceState
        self.modelName = modelName
        self.tailDuration = tailDuration
        setUpForwarding()
    }

    private func setUpForwarding() {
        recorder.onBuffer = Self.coalescingForwarder(merge: { AudioBufferSummary.coalescing($0, $1) }) { [weak self] summary in
            self?.onSpectrum?(summary.spectrum)
            self?.observeLevel(peak: summary.peak, at: summary.time)
        }
    }

    // CoreAudio reads can block on a Bluetooth device, so they run off the main actor and apply when they arrive.
    private func readInputDeviceState(for id: Int) {
        let reader = inputDeviceState
        Task.detached(priority: .userInitiated) { [weak self] in
            let state = reader.currentState()
            await self?.applyInputDeviceState(state, for: id)
        }
    }

    private func applyInputDeviceState(_ state: InputDeviceState, for id: Int) {
        guard id == recordingID else { return }
        deviceSeemedMuted = state.seemsMuted
        guard isRecording, var detector = muteDetector else { return }
        let changed = detector.applyDeviceState(state)
        muteDetector = detector
        if changed {
            onMicrophoneMutedChange?(detector.isMuted)
        }
    }

    // Tail buffers after release belong to no live recording, so only buffers while recording are judged.
    private func observeLevel(peak: Float, at time: TimeInterval) {
        guard isRecording, var detector = muteDetector else { return }
        let changed = detector.observe(peak: peak, at: time)
        muteDetector = detector
        if changed {
            onMicrophoneMutedChange?(detector.isMuted)
        }
    }

    // Merges values that arrive before the main actor gets to them, so a busy main actor gets one hop per burst.
    private static func coalescingForwarder<Value: Sendable>(
        merge: @escaping @Sendable (Value, Value) -> Value,
        _ deliver: @escaping @Sendable @MainActor (Value) -> Void
    ) -> @Sendable (Value) -> Void {
        let pending = OSAllocatedUnfairLock<Value?>(initialState: nil)
        return { value in
            let shouldSchedule = pending.withLock { state -> Bool in
                defer { state = state.map { merge($0, value) } ?? value }
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
        isModelReady = false
        onModelReadyChange?(false)
        Task {
            if await !self.loadModel() { self.onIssue?(.modelNotLoaded) }
        }
    }

    // The caller reports a failure: after a failed update the previous model may still load fine.
    @discardableResult
    public func reloadModel() async -> Bool {
        isModelReady = false
        onModelReadyChange?(false)
        await engine.unload()
        return await loadModel()
    }

    private func loadModel() async -> Bool {
        let start = Date()
        do {
            try await engine.prepare()
            logger.info("model ready: \(self.modelName, privacy: .public) in \(Self.format(Date().timeIntervalSince(start)), privacy: .public)")
            isModelReady = true
            onModelReadyChange?(true)
            return true
        } catch {
            logger.error("model preparation failed: \(self.modelName, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    @discardableResult
    public func startRecording() -> Bool {
        guard !isRecording, !isCapturingTail else { return false }
        guard !PermissionsManager.isMicrophoneAccessDenied() else {
            logger.error("recording refused: microphone access denied")
            onIssue?(.microphoneAccessNeeded)
            return false
        }
        do {
            try recorder.start()
            isRecording = true
            recordingID = phaseTracker.beginRecording()
            deviceSeemedMuted = false
            muteDetector = MicrophoneMuteDetector()
            readInputDeviceState(for: recordingID)
            onStateChange?(true)
            onPhaseChange?(.recording)
            onMicrophoneMutedChange?(false)
            return true
        } catch {
            logger.error("failed to start recording: \(String(describing: error), privacy: .public)")
            onIssue?(.noInputDevice)
            return false
        }
    }

    @discardableResult
    public func stopRecordingAndTranscribe() -> Bool {
        guard isRecording else { return false }
        isRecording = false
        isCapturingTail = true
        onStateChange?(false)
        let minimumSilence = muteDetector?.requiredSilence ?? MicrophoneMuteDetector.silenceDuration
        muteDetector = nil
        let deviceSeemedMuted = self.deviceSeemedMuted
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

            let audioSeconds = Double(samples.count) / 16_000
            let peakAmplitude = samples.reduce(into: Float(0)) { peak, sample in peak = max(peak, abs(sample)) }
            switch RecordingCheck.assess(
                sampleCount: samples.count,
                peak: peakAmplitude,
                deviceSeemsMuted: deviceSeemedMuted,
                minimumSilence: minimumSilence
            ) {
            case .empty:
                self.logger.info("no audio captured")
                self.onCue?(.nothingHeard)
                return
            case .tooShort:
                self.logger.info("recording too short: \(Self.format(audioSeconds), privacy: .public)")
                self.onCue?(.nothingHeard)
                return
            case .digitalSilence:
                self.logger.info("recording was digital silence: \(Self.format(audioSeconds), privacy: .public), device muted=\(deviceSeemedMuted, privacy: .public)")
                self.onCue?(.microphoneMuted)
                return
            case .transcribable:
                break
            }

            do {
                let text = try await engine.transcribe(samples)
                guard !text.isEmpty else {
                    self.logger.info("\(modelName, privacy: .public): empty transcription: \(Self.format(audioSeconds), privacy: .public) audio, peak=\(peakAmplitude, privacy: .public)")
                    self.onCue?(.noText)
                    return
                }
                self.lastTranscript = text

                let frontmostPIDAtDelivery = NSWorkspace.shared.frontmostApplication?.processIdentifier
                guard PasteService.shouldAutoPaste(
                    frontmostPIDAtRelease: frontmostPIDAtRelease,
                    frontmostPIDAtDelivery: frontmostPIDAtDelivery
                ) else {
                    PasteService.writeToPasteboard(text)
                    self.logger.info("paste skipped (frontmost app changed)")
                    self.onCue?(.textOnClipboard)
                    return
                }

                let outcome = self.issuePaste(text)
                self.updatePhase { $0.finish(dictationID) }
                self.logger.info("\(modelName, privacy: .public): \(Self.format(audioSeconds), privacy: .public) audio -> pasted in \(Self.format(Date().timeIntervalSince(released)), privacy: .public) pasted=\(outcome.pasted, privacy: .public): \(text, privacy: .private)")
                await self.settleClipboard(outcome)
            } catch {
                self.logger.error("\(modelName, privacy: .public): transcription failed: \(String(describing: error), privacy: .public)")
                self.onIssue?(.transcriptionFailed)
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
            ? clipboardOwnership.begin(changeCount: NSPasteboard.general.changeCount) { PasteService.snapshot() }.generation
            : nil
        let changeCountAfterWrite = PasteService.writeToPasteboard(text, transient: keepClipboardContent)
        if let generation {
            clipboardOwnership.didWrite(changeCount: changeCountAfterWrite, generation: generation)
        }
        PasteService.paste()
        let pasted = AXIsProcessTrusted()
        if pasted {
            onPaste?()
        } else {
            onIssue?(.accessibilityAccessNeeded)
        }
        return PasteOutcome(pasted: pasted, generation: generation, changeCountAfterWrite: changeCountAfterWrite, keepClipboardContent: keepClipboardContent)
    }

    // Restores the user's original clipboard once the paste has had time to land, unless it was superseded or changed.
    private func settleClipboard(_ outcome: PasteOutcome) async {
        guard let generation = outcome.generation else { return }
        guard outcome.pasted else {
            clipboardOwnership.cancel(generation: generation)
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
        muteDetector = nil
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
