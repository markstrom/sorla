import Foundation
import os

// Timings and outcomes of recent dictations for device testing. It never holds audio or transcript text.
@MainActor
final class DictationLog: ObservableObject {
    static let capacity = 50
    private static let key = "dictation.metrics"
    private static let logger = Logger(subsystem: "com.sorla.ios", category: "Dictation")

    @Published private(set) var entries: [DictationMetric]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([DictationMetric].self, from: $0) } ?? []
    }

    func append(_ metric: DictationMetric) {
        entries = Array((entries + [metric]).suffix(Self.capacity))
        defaults.set(try? JSONEncoder().encode(entries), forKey: Self.key)
        Self.logger.info("""
            dictation \(metric.outcome, privacy: .public) active=\(metric.appWasActive, privacy: .public) \
            listening=\(Self.format(metric.invocationToListeningMs), privacy: .public)ms \
            result=\(Self.format(metric.stopToResultMs), privacy: .public)ms \
            audio=\(Self.format(metric.audioSeconds), privacy: .public)s \
            bg=\(Self.format(metric.backgroundSecondsRemainingAtStop), privacy: .public)s
            """)
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: Self.key)
    }

    var markdown: String {
        var lines = [
            "| Time | Outcome | App active | Trigger→listening (ms) | Stop→result (ms) | Audio (s) | Background left at stop (s) | Model ready at stop | Capture ended |",
            "|---|---|---|---|---|---|---|---|---|",
        ]
        let formatter = ISO8601DateFormatter()
        for entry in entries {
            lines.append("| \(formatter.string(from: entry.date)) | \(entry.outcome) | \(entry.appWasActive ? "yes" : "no") | \(Self.format(entry.invocationToListeningMs)) | \(Self.format(entry.stopToResultMs)) | \(Self.format(entry.audioSeconds)) | \(Self.format(entry.backgroundSecondsRemainingAtStop)) | \(entry.modelWasReadyAtStop.map { $0 ? "yes" : "no" } ?? "–") | \(entry.captureEnd ?? "–") |")
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func format(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.1f", value)
    }
}
