import AVFoundation
import SwiftUI
import UIKit

// Setup and diagnostics for the Action Button prototype. Normal use happens from the Shortcut, not here.
struct DictationView: View {
    @ObservedObject var runtime: DictationRuntime
    @ObservedObject var log: DictationLog
    @ObservedObject var modelSetup: ModelSetup
    @State private var microphone = AVAudioApplication.shared.recordPermission

    var body: some View {
        NavigationStack {
            List {
                Section("Ready to dictate") {
                    ChecklistRow(title: "Microphone allowed", done: microphone == .granted)
                    if microphone == .undetermined {
                        Button("Allow Microphone") {
                            Task {
                                _ = await AVAudioApplication.requestRecordPermission()
                                microphone = AVAudioApplication.shared.recordPermission
                            }
                        }
                    } else if microphone == .denied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                    ChecklistRow(title: "Speech model installed", done: modelSetup.installed != nil)
                }

                Section {
                    Button("Start or Stop (same as the Shortcut)") {
                        Task { _ = await runtime.toggle() }
                    }
                    Button("Cancel", role: .destructive) {
                        Task { await runtime.cancel() }
                    }
                    if let message = runtime.lastMessage {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Try it here")
                } footer: {
                    Text("This button returns the result to nobody, so nothing is copied. Use the Shortcut to copy text.")
                }

                Section {
                    Text("Create a Shortcut: “Diktera med Sorla”, then “If Ready to Paste is true”, “Copy Text to Clipboard”. Assign it to the Action Button or Back Tap. iOS/Docs/action-button.md has the exact steps.")
                        .font(.callout)
                } header: {
                    Text("Action Button")
                }

                Section {
                    if log.entries.isEmpty {
                        Text("No dictations yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(log.entries.suffix(10).reversed().enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.outcome)
                                .font(.headline)
                            Text(Self.summary(entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !log.entries.isEmpty {
                        Button("Copy Log as Markdown") {
                            UIPasteboard.general.string = log.markdown
                        }
                        Button("Clear Log", role: .destructive) {
                            log.clear()
                        }
                    }
                } header: {
                    Text("Recent dictations (timings only)")
                }
            }
            .navigationTitle("Sorla")
            .onAppear {
                microphone = AVAudioApplication.shared.recordPermission
                modelSetup.refresh()
            }
        }
    }

    private static func summary(_ entry: DictationMetric) -> String {
        var parts = [entry.date.formatted(date: .omitted, time: .standard), entry.appWasActive ? "foreground" : "background"]
        if let value = entry.invocationToListeningMs { parts.append("listening after \(DictationLog.format(value)) ms") }
        if let value = entry.stopToResultMs { parts.append("result after \(DictationLog.format(value)) ms") }
        if let value = entry.audioSeconds { parts.append("\(DictationLog.format(value)) s audio") }
        if let value = entry.backgroundSecondsRemainingAtStop { parts.append("\(DictationLog.format(value)) s background left") }
        return parts.joined(separator: " · ")
    }
}

struct ChecklistRow: View {
    let title: String
    let done: Bool

    var body: some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? .primary : .secondary)
            .accessibilityValue(done ? "Done" : "Not done")
    }
}
