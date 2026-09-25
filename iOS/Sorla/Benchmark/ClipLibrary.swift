import AVFoundation
import Foundation

// A test utterance held in memory at its own sample rate, as a microphone would deliver it.
struct BenchmarkClip: Identifiable, Equatable, Sendable {
    enum Source: String, Sendable {
        case bundled
        case documents
        case recorded
    }

    var id: String { "\(source.rawValue)/\(name)" }
    var name: String
    var source: Source
    var samples: [Float]
    var sampleRate: Double

    var seconds: Double { Double(samples.count) / sampleRate }
}

enum ClipLibrary {
    static let bundledFolder = "Utterances"
    static let audioExtensions: Set<String> = ["wav", "aif", "aiff", "caf", "m4a"]

    static var documentsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundledFolder, isDirectory: true)
    }

    // Bundled clips come from iOS/Benchmark/Utterances at build time; testers can add their own
    // recordings to Documents/Utterances through Finder or the Files app.
    static func load() -> [BenchmarkClip] {
        try? FileManager.default.createDirectory(at: documentsFolder, withIntermediateDirectories: true)
        var clips: [BenchmarkClip] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent(bundledFolder, isDirectory: true) {
            clips += load(from: bundled, source: .bundled)
        }
        clips += load(from: documentsFolder, source: .documents)
        return clips
    }

    static func load(from folder: URL, source: BenchmarkClip.Source) -> [BenchmarkClip] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { try? readClip($0, source: source) }
    }

    static func readClip(_ url: URL, source: BenchmarkClip.Source) throws -> BenchmarkClip {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioRecorderError.bufferAllocationFailed
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw AudioRecorderError.bufferAllocationFailed }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        return BenchmarkClip(
            name: url.deletingPathExtension().lastPathComponent,
            source: source,
            samples: samples,
            sampleRate: format.sampleRate
        )
    }
}
