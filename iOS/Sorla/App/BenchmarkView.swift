import SwiftUI
import UIKit

struct BenchmarkView: View {
    @ObservedObject var runner: BenchmarkRunner

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if runner.clips.isEmpty {
                        Text("No clips yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(runner.clips) { clip in
                        LabeledContent(clip.name, value: String(format: "%.1f s · %@", clip.seconds, clip.source.rawValue))
                    }
                    Button(runner.isRecordingClip ? "Stop Recording Clip" : "Record a Clip (kept in memory only)") {
                        runner.toggleClipRecording()
                    }
                    .disabled(runner.isRunning)
                    Button("Reload Clips") { runner.reloadClips() }
                        .disabled(runner.isRunning || runner.isRecordingClip)
                } header: {
                    Text("Utterances")
                } footer: {
                    Text("Bundled clips come from iOS/Benchmark/make-utterances.sh. Add real recordings to Documents/Utterances via Finder or the Files app.")
                }

                Section("Run") {
                    Stepper("Runs per clip: \(runner.repetitions)", value: $runner.repetitions, in: 1...20)
                    Toggle("Reload after cleanup", isOn: $runner.reloadAfterCleanup)
                    Button(runner.isRunning ? "Running…" : "Run Benchmark") {
                        Task { await runner.run() }
                    }
                    .disabled(runner.isRunning || runner.isRecordingClip)
                    if let status = runner.status {
                        Text(status)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let preview = runner.lastTranscriptPreview {
                        Text(preview)
                            .font(.callout)
                            .accessibilityLabel("Last transcript preview: \(preview)")
                    }
                }

                if let report = runner.report {
                    Section("Results") {
                        Text(report.markdown)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Button("Copy as Markdown") {
                            UIPasteboard.general.string = report.markdown
                        }
                        ShareLink(item: report.markdown) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle("Benchmark")
        }
    }
}
