import Foundation
import os

@MainActor
public final class RecordingController {
    let recorder: AudioRecorder
    private let engine: TranscriptionEngine
    private let inputDeviceState: InputDeviceStateReading
    private let isMicrophoneAccessDenied: @MainActor () -> Bool
    private let sleep: @MainActor (Duration) async -> Void
    private let now: @MainActor () -> ContinuousClock.Instant
    private let waitForTimeLimit: @MainActor (Duration) async -> Void
    private let modelName: String
    public let tailDuration: TimeInterval
    private let logger = Logger(subsystem: "com.sorla.app", category: "RecordingController")

    public private(set) var isRecording = false
    private var isCapturingTail = false
    // The microphone stays open for the tail after release, so this outlasts isRecording.
    public var isMicrophoneOpen: Bool { isRecording || isCapturingTail }
    public var onMicrophoneClosed: (() -> Void)?
    public var onStateChange: ((Bool) -> Void)?
    public var onSpectrum: ((SIMD8<Float>) -> Void)?
    public var onPhaseChange: ((DictationPhase) -> Void)?
    public var onCue: ((DictationCue) -> Void)?
    public var onMicrophoneMutedChange: ((Bool) -> Void)?
    public var onPaste: (() -> Void)?
    private var muteDetector: MicrophoneMuteDetector?
    private var deviceSeemedMuted = false
    public var phase: DictationPhase { phaseTracker.phase }

    // What an update or restart has to wait for, not just what the indicator shows.
    public var activity: DictationActivity {
        DictationActivity(
            isRecording: isRecording,
            isCapturingTail: isCapturingTail,
            isTranscribing: phase != .idle,
            pendingDeliveries: pendingDeliveries,
            isPasteLastInFlight: isPasteLastInFlight,
            isRestoringClipboard: pendingClipboardRestores > 0
        )
    }
    private var phaseTracker = DictationPhaseTracker()
    private var recordingID = 0
    public var keepClipboardContent = true
    private var clipboardOwnership = ClipboardOwnershipTracker()

    public private(set) var isModelReady = false
    public var onModelReadyChange: ((Bool) -> Void)?
    public var onIssue: ((SorlaIssue) -> Void)?
    // Asked just before each ⌘V: a replaced app's paste would be dropped without a word.
    public var isAppReplaced: () -> Bool = { false }
    // After the issue: the text was left on the clipboard, and this says how to tell it is still there (#72).
    public var onPasteBlocked: ((BlockedPaste) -> Void)?

    private var recentTranscript = RecentTranscript()
    private var transcriptExpiry: Task<Void, Never>?
    private var isPasteLastInFlight = false
    private(set) var pasteLastRequest: Task<Void, Never>?
    // Bumped when a waiting Paste Last is called off, since it may already be queued behind a delivery.
    private var pasteLastToken = 0

    // Off, Paste Last has nothing to recover: no text is kept, and turning it off forgets what was.
    public var keepsLastTranscript = true {
        didSet {
            guard !keepsLastTranscript else { return }
            transcriptExpiry?.cancel()
            transcriptExpiry = nil
            cancelPasteLast()
            recentTranscript.clear()
        }
    }

    private let pasteEnvironment: PasteEnvironment
    private var deliveryOrder = DeliveryOrder<FinishedDictation>()
    private(set) var dictationJobs: [Int: Task<Void, Never>] = [:]
    private(set) var deliveries: Task<Void, Never>?
    private var lastPasteAt: ContinuousClock.Instant?
    private(set) var clipboardRestore: Task<Void, Never>?
    private var pendingDeliveries = 0
    private var pendingClipboardRestores = 0
    // Lets tests wait until a request has taken its place in line.
    var didEnqueueDelivery: (() -> Void)?

    public init(
        engine: TranscriptionEngine,
        modelName: String,
        tailDuration: TimeInterval = 0.15,
        inputDeviceState: InputDeviceStateReading = CoreAudioInputDeviceState(),
        recorder: AudioRecorder = AudioRecorder(),
        pasteEnvironment: PasteEnvironment = SystemPasteEnvironment(),
        isMicrophoneAccessDenied: @escaping @MainActor () -> Bool = { PermissionsManager.isMicrophoneAccessDenied() },
        sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        now: @escaping @MainActor () -> ContinuousClock.Instant = { .now },
        waitForTimeLimit: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.engine = engine
        self.inputDeviceState = inputDeviceState
        self.recorder = recorder
        self.pasteEnvironment = pasteEnvironment
        self.isMicrophoneAccessDenied = isMicrophoneAccessDenied
        self.sleep = sleep
        self.now = now
        self.waitForTimeLimit = waitForTimeLimit
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
        guard !isMicrophoneAccessDenied() else {
            logger.error("recording refused: microphone access denied")
            onIssue?(.microphoneAccessNeeded)
            return false
        }
        do {
            try recorder.start()
            // The new dictation owns the cursor now.
            cancelPasteLast()
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
        let generation = recentTranscript.generation
        updatePhase { $0.release(dictationID) }
        deliveryOrder.expect(dictationID)

        let released = Date()
        let frontmostPIDAtRelease = pasteEnvironment.frontmostProcessID

        dictationJobs[dictationID] = Task { @MainActor in
            let result = await self.transcribe(
                generation: generation,
                deviceSeemedMuted: deviceSeemedMuted,
                minimumSilence: minimumSilence
            )
            self.dictationJobs[dictationID] = nil
            self.finishDictation(FinishedDictation(
                id: dictationID,
                generation: generation,
                result: result,
                frontmostPIDAtRelease: frontmostPIDAtRelease,
                released: released
            ))
        }
        return true
    }

    private enum DictationResult {
        case dropped
        case cue(DictationCue)
        case failed
        case text(String, audioSeconds: Double)
    }

    private struct FinishedDictation {
        let id: Int
        let generation: Int
        let result: DictationResult
        let frontmostPIDAtRelease: pid_t?
        let released: Date
    }

    // The audio lives only in here, so it is let go as soon as the transcription is done.
    private func transcribe(generation: Int, deviceSeemedMuted: Bool, minimumSilence: TimeInterval) async -> DictationResult {
        await sleep(.seconds(tailDuration))
        // Locked during the tail: the audio would only be transcribed to be thrown away.
        let isForgotten = !recentTranscript.accepts(from: generation)
        let samples: [Float]
        do {
            samples = try endTail(keepingAudio: !isForgotten)
        } catch {
            logger.error("failed to stop recording: \(String(describing: error), privacy: .public)")
            return .dropped
        }
        guard !isForgotten else {
            logger.info("recording dropped (the Mac locked, slept or switched user)")
            return .dropped
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
            logger.info("no audio captured")
            return .cue(.nothingHeard)
        case .tooShort:
            logger.info("recording too short: \(Self.format(audioSeconds), privacy: .public)")
            return .cue(.nothingHeard)
        case .digitalSilence:
            logger.info("recording was digital silence: \(Self.format(audioSeconds), privacy: .public), device muted=\(deviceSeemedMuted, privacy: .public)")
            return .cue(.microphoneMuted)
        case .transcribable:
            break
        }

        switch await transcribe(samples, within: Self.transcriptionTimeLimit(audioSeconds: audioSeconds)) {
        case .text(let text):
            guard !text.isEmpty else {
                logger.info("\(self.modelName, privacy: .public): empty transcription: \(Self.format(audioSeconds), privacy: .public) audio, peak=\(peakAmplitude, privacy: .public)")
                return .cue(.noText)
            }
            return .text(text, audioSeconds: audioSeconds)
        case .failed(let error):
            logger.error("\(self.modelName, privacy: .public): transcription failed: \(String(describing: error), privacy: .public)")
            return .failed
        case .timedOut:
            logger.error("\(self.modelName, privacy: .public): transcription timed out: \(Self.format(audioSeconds), privacy: .public) audio")
            return .failed
        }
    }

    // Generous, since a slow Mac is not a hung one; it only has to end a wait that would never end.
    public static func transcriptionTimeLimit(audioSeconds: Double) -> Duration {
        .seconds(max(30, 3 * audioSeconds))
    }

    private enum Transcription {
        case text(String)
        case failed(Error)
        case timedOut
    }

    // A hung engine call is left behind, so the recordings after it are not held up.
    private func transcribe(_ samples: [Float], within limit: Duration) async -> Transcription {
        let engine = self.engine
        let waitForTimeLimit = self.waitForTimeLimit
        return await withCheckedContinuation { continuation in
            let outcome = FirstOutcome(continuation)
            let timer = Task { @MainActor in
                await waitForTimeLimit(limit)
                outcome.resolve(.timedOut)
            }
            Task { @MainActor in
                do {
                    outcome.resolve(.text(try await engine.transcribe(samples)))
                } catch {
                    outcome.resolve(.failed(error))
                }
                timer.cancel()
            }
        }
    }

    @MainActor
    private final class FirstOutcome {
        private var continuation: CheckedContinuation<Transcription, Never>?

        init(_ continuation: CheckedContinuation<Transcription, Never>) {
            self.continuation = continuation
        }

        func resolve(_ transcription: Transcription) {
            continuation?.resume(returning: transcription)
            continuation = nil
        }
    }

    private func endTail(keepingAudio: Bool) throws -> [Float] {
        defer {
            isCapturingTail = false
            onMicrophoneClosed?()
        }
        guard keepingAudio else {
            recorder.cancel()
            return []
        }
        return try recorder.stop()
    }

    // A lock empties the delivery order, so a dictation from before it has nothing left to wait for.
    private func finishDictation(_ finished: FinishedDictation) {
        guard recentTranscript.accepts(from: finished.generation) else {
            logger.info("transcription dropped (the Mac locked, slept or switched user)")
            updatePhase { $0.finish(finished.id) }
            return
        }
        for due in deliveryOrder.finish(finished.id, with: finished) {
            enqueueDelivery { await self.deliver(due) }
        }
    }

    // Results and Paste Last are handled one after another, in order; only a pasteboard write waits for the last ⌘V.
    @discardableResult
    private func enqueueDelivery(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        didEnqueueDelivery?()
        let previous = deliveries
        pendingDeliveries += 1
        let delivery = Task { @MainActor in
            defer { self.pendingDeliveries -= 1 }
            await previous?.value
            await work()
        }
        deliveries = delivery
        return delivery
    }

    // Checked again here, since a lock or a switch of app may have come while this waited its turn.
    private func deliver(_ finished: FinishedDictation) async {
        let dictationID = finished.id
        defer { updatePhase { $0.finish(dictationID) } }
        if case .text = finished.result {
            await waitForThePreviousPasteToLand()
        }
        guard recentTranscript.accepts(from: finished.generation) else {
            logger.info("transcription dropped (the Mac locked, slept or switched user)")
            return
        }
        switch finished.result {
        case .dropped:
            return
        case .cue(let cue):
            onCue?(cue)
        case .failed:
            onIssue?(.transcriptionFailed)
        case .text(let text, let audioSeconds):
            keepLastTranscript(text)
            guard PasteService.shouldAutoPaste(
                frontmostPIDAtRelease: finished.frontmostPIDAtRelease,
                frontmostPIDAtDelivery: pasteEnvironment.frontmostProcessID
            ) else {
                pasteEnvironment.write(text, transient: false)
                logger.info("paste skipped (frontmost app changed)")
                onCue?(.textOnClipboard)
                return
            }
            guard !leaveOnClipboardIfReplaced(text) else { return }

            let outcome = issuePaste(text)
            updatePhase { $0.finish(dictationID) }
            logger.info("\(self.modelName, privacy: .public): \(Self.format(audioSeconds), privacy: .public) audio -> pasted in \(Self.format(Date().timeIntervalSince(finished.released)), privacy: .public) pasted=\(outcome.pasted, privacy: .public): \(text, privacy: .private)")
            restoreClipboard(after: outcome)
        }
    }

    public func lastTranscript(at now: Date = Date()) -> String? {
        recentTranscript.text(at: now)
    }

    public func lastTranscriptRevision(at now: Date = Date()) -> Int? {
        recentTranscript.text(at: now) == nil ? nil : recentTranscript.revision
    }

    // Copy Text in the window about a blocked paste: the clipboard only changes because the user asked (#72).
    // Returns the clipboard's change count, or nil when that text is no longer kept.
    public func copyLastTranscript(revision: Int?) -> Int? {
        guard let revision, revision == lastTranscriptRevision(), let text = lastTranscript() else { return nil }
        return pasteEnvironment.write(text, transient: false)
    }

    // One one-shot expiry per transcript, replaced by the next one, so nothing runs while idle.
    private func keepLastTranscript(_ text: String) {
        guard keepsLastTranscript else { return }
        recentTranscript.store(text, at: Date())
        transcriptExpiry?.cancel()
        transcriptExpiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(RecentTranscript.lifetime))
            guard !Task.isCancelled else { return }
            self?.recentTranscript.clear()
        }
    }

    // Also drops a transcription still in flight, which would otherwise paste and keep its text afterwards.
    public func forgetLastTranscript() {
        transcriptExpiry?.cancel()
        transcriptExpiry = nil
        cancelPasteLast()
        recentTranscript.forget()
        for dropped in deliveryOrder.dropAll() {
            updatePhase { $0.finish(dropped.id) }
        }
    }

    // Pastes the most recent successful transcript at the current cursor, same path as a dictation.
    public func pasteLastTranscript(after prepare: @escaping @MainActor () async -> PasteLastPreparation = { .ready }) {
        let lastTranscript = lastTranscript()
        guard PasteService.shouldPasteLast(
            hasTranscript: lastTranscript != nil,
            phase: phase,
            isPasteLastInFlight: isPasteLastInFlight
        ), let text = lastTranscript else {
            logger.info("paste-last skipped (no transcript, or a dictation or paste-last in progress)")
            // A dictation in progress pastes its own text, so only an idle request is told there's nothing.
            if lastTranscript == nil, phase == .idle {
                onCue?(.nothingToPaste)
            }
            return
        }
        isPasteLastInFlight = true
        let generation = recentTranscript.generation
        let token = pasteLastToken
        pasteLastRequest = Task { @MainActor in
            defer { self.isPasteLastInFlight = false }
            let preparation = await prepare()
            guard preparation != .abandoned, !Task.isCancelled else {
                self.logger.info("paste-last skipped (abandoned before pasting)")
                return
            }
            await self.enqueueDelivery {
                if preparation == .ready {
                    await self.waitForThePreviousPasteToLand()
                }
                guard self.recentTranscript.accepts(from: generation), token == self.pasteLastToken else {
                    self.logger.info("paste-last skipped (the text was forgotten)")
                    return
                }
                guard self.phase == .idle else {
                    self.logger.info("paste-last skipped (dictation started)")
                    return
                }
                // The clipboard is the user's, so the text stays with Paste Last for another try.
                guard preparation == .ready else {
                    self.logger.info("paste-last not pasted (shortcut keys still held)")
                    self.onCue?(.releaseKeys)
                    return
                }
                guard !self.leaveOnClipboardIfReplaced(text) else { return }
                let outcome = self.issuePaste(text)
                self.logger.info("paste-last: pasted=\(outcome.pasted, privacy: .public)")
                self.restoreClipboard(after: outcome)
            }.value
        }
    }

    private func leaveOnClipboardIfReplaced(_ text: String) -> Bool {
        guard isAppReplaced() else { return false }
        let changeCount = pasteEnvironment.write(text, transient: false)
        logger.info("paste skipped (Sorla was replaced on disk)")
        onIssue?(.appReplaced)
        // Only the clipboard outlives the restart this needs, so the text stays there whatever the setting.
        onPasteBlocked?(BlockedPaste(reason: .appReplaced, clipboardChangeCount: changeCount, transcriptRevision: lastTranscriptRevision()))
        return true
    }

    private func cancelPasteLast() {
        pasteLastRequest?.cancel()
        pasteLastToken += 1
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
        let pasteEnvironment = self.pasteEnvironment
        let generation: Int? = keepClipboardContent
            ? clipboardOwnership.begin(changeCount: pasteEnvironment.changeCount) { pasteEnvironment.snapshot() }.generation
            : nil
        let changeCountAfterWrite = pasteEnvironment.write(text, transient: keepClipboardContent)
        if let generation {
            clipboardOwnership.didWrite(changeCount: changeCountAfterWrite, generation: generation)
        }
        let pasted = pasteEnvironment.paste()
        if pasted {
            lastPasteAt = now()
            onPaste?()
        } else {
            onIssue?(.accessibilityAccessNeeded)
        }
        return PasteOutcome(pasted: pasted, generation: generation, changeCountAfterWrite: changeCountAfterWrite, keepClipboardContent: keepClipboardContent)
    }

    // The app reads the pasteboard only when it handles the ⌘V, so nothing may be written before then.
    private func waitForThePreviousPasteToLand() async {
        if let lastPasteAt {
            let remaining = Self.pasteSettleTime - (now() - lastPasteAt)
            if remaining > .zero {
                await sleep(remaining)
            }
        }
        await clipboardRestore?.value
    }

    // Once the paste has had time to land, puts back the user's clipboard unless it was superseded or changed.
    private func restoreClipboard(after outcome: PasteOutcome) {
        guard outcome.pasted else { return keepBlockedText(after: outcome) }
        guard let generation = outcome.generation else { return }
        pendingClipboardRestores += 1
        clipboardRestore = Task { @MainActor in
            defer { self.pendingClipboardRestores -= 1 }
            await self.sleep(Self.pasteSettleTime)
            switch self.clipboardOwnership.finish(generation: generation) {
            case .skip:
                self.logger.info("clipboard kept (superseded)")
            case .evaluate(let original):
                if PasteService.shouldRestoreClipboard(
                    keepSetting: outcome.keepClipboardContent,
                    pasteDelivered: outcome.pasted,
                    changeCountAfterWrite: outcome.changeCountAfterWrite,
                    currentChangeCount: self.pasteEnvironment.changeCount
                ) {
                    self.pasteEnvironment.restore(original)
                    self.logger.info("clipboard restored")
                } else {
                    self.logger.info("clipboard kept (clipboard changed)")
                }
            }
        }
    }

    // Nothing reached the app (#72). With "Put back what you had copied" on, the user's clipboard goes back at once
    // and only Sorla holds the text, for Paste Last and the window's buttons; with it off, or with nothing kept
    // (Keep last transcription off), the text stays on the clipboard for the user's own ⌘V.
    private func keepBlockedText(after outcome: PasteOutcome) {
        let revision = lastTranscriptRevision()
        var clipboardChangeCount: Int? = outcome.changeCountAfterWrite
        if let generation = outcome.generation {
            if revision != nil, case .evaluate(let original) = clipboardOwnership.finish(generation: generation) {
                if pasteEnvironment.changeCount == outcome.changeCountAfterWrite {
                    pasteEnvironment.restore(original)
                    clipboardChangeCount = nil
                    logger.info("clipboard restored (paste blocked, text kept)")
                }
            } else {
                clipboardOwnership.cancel(generation: generation)
                logger.info("clipboard kept (not pasted)")
            }
        }
        onPasteBlocked?(BlockedPaste(reason: .accessibility, clipboardChangeCount: clipboardChangeCount, transcriptRevision: revision))
    }

    static let pasteSettleTime: Duration = .milliseconds(500)

    public func cancelRecording() {
        guard isRecording else { return }
        recorder.cancel()
        isRecording = false
        muteDetector = nil
        onStateChange?(false)
        onMicrophoneClosed?()
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
