import Foundation
@testable import SorlaCore

// Stands in for the microphone: frames arrive only when a test feeds them.
final class FakeAudioInput: AudioInput {
    var sampleRate: Double = 16_000
    private(set) var isRunning = false
    private var onFrames: ((UnsafeBufferPointer<Float>) -> Void)?

    func prepare() throws -> Double { sampleRate }

    func start(onFrames: @escaping (UnsafeBufferPointer<Float>) -> Void) throws {
        self.onFrames = onFrames
        isRunning = true
    }

    func stop() {
        onFrames = nil
        isRunning = false
    }

    func feed(_ value: Float = 0.25, count: Int = SpectrumAnalyzer.frameCount) {
        let frames = [Float](repeating: value, count: count)
        frames.withUnsafeBufferPointer { onFrames?($0) }
    }
}

// Counts conversions and can be told to fail, in place of the real resampler.
final class FakeResampler {
    private(set) var calls = 0
    var error: Error?

    func resample(_ samples: [Float], sampleRate: Double) throws -> [Float] {
        calls += 1
        if let error { throw error }
        return samples
    }
}

extension AudioRecorder {
    convenience init(input: FakeAudioInput, resampler: FakeResampler) {
        self.init(input: input, resample: { try resampler.resample($0, sampleRate: $1) })
    }
}

struct SilentInputDevice: InputDeviceStateReading {
    func currentState() -> InputDeviceState { InputDeviceState(isMuted: false, volume: 1, isBluetooth: false) }
}

// Each transcription waits until the test finishes it, so tests choose the order results arrive in.
actor HeldTranscriptionEngine: TranscriptionEngine {
    private(set) var sampleCounts: [Int] = []
    private var held: [Int: CheckedContinuation<String, Error>] = [:]
    private var callWaiters: [(count: Int, resume: CheckedContinuation<Void, Never>)] = []

    func prepare() async throws {}
    func unload() async {}

    func transcribe(_ samples: [Float]) async throws -> String {
        let call = sampleCounts.count
        sampleCounts.append(samples.count)
        let count = sampleCounts.count
        callWaiters.filter { $0.count <= count }.forEach { $0.resume.resume() }
        callWaiters.removeAll { $0.count <= count }
        return try await withCheckedThrowingContinuation { held[call] = $0 }
    }

    // Returns once `count` transcriptions have started.
    func waitForCalls(_ count: Int) async {
        guard sampleCounts.count < count else { return }
        await withCheckedContinuation { callWaiters.append((count, $0)) }
    }

    func finish(_ call: Int, with text: String) {
        held.removeValue(forKey: call)?.resume(returning: text)
    }

    func fail(_ call: Int) {
        held.removeValue(forKey: call)?.resume(throwing: CocoaError(.fileReadCorruptFile))
    }
}

// A pasteboard and frontmost app in memory; each ⌘V records the text the app would have read.
@MainActor
final class FakePasteEnvironment: PasteEnvironment {
    var frontmostProcessID: pid_t? = 100
    var isAccessibilityTrusted = true
    private(set) var changeCount = 0
    private(set) var contents: String?
    private(set) var writes: [String] = []
    private(set) var pastes: [String] = []
    private(set) var events: [String] = []
    private(set) var lastWriteWasTransient: Bool?

    nonisolated init() {}

    func snapshot() -> PasteboardSnapshot {
        PasteboardSnapshot(items: contents.map { [.init(data: [.string: Data($0.utf8)])] } ?? [])
    }

    func write(_ text: String, transient: Bool) -> Int {
        contents = text
        lastWriteWasTransient = transient
        writes.append(text)
        events.append("write \(text)")
        changeCount += 1
        return changeCount
    }

    // The user copying something of their own.
    func copy(_ text: String) {
        contents = text
        changeCount += 1
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        contents = snapshot.items.first?.data[.string].map { String(decoding: $0, as: UTF8.self) }
        events.append("restore")
        changeCount += 1
    }

    func paste() -> Bool {
        guard isAccessibilityTrusted else { return false }
        pastes.append(contents ?? "")
        events.append("paste \(contents ?? "")")
        return true
    }
}
