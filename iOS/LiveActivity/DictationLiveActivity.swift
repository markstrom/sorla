import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct SorlaLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        DictationLiveActivity()
    }
}

// Shown only while a dictation is in progress; AudioRecordingIntent requires it for background recording.
struct DictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationActivityAttributes.self) { context in
            LockScreenDictationView(state: context.state)
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.phase.symbolName)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.phase.title)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedTime(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.phase.isCancellable {
                        Button(intent: CancelDictationIntent()) {
                            Label("Cancel", systemImage: "xmark")
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.phase.symbolName)
                    .accessibilityLabel(context.state.phase.title)
            } compactTrailing: {
                ElapsedTime(state: context.state)
            } minimal: {
                Image(systemName: context.state.phase.symbolName)
                    .accessibilityLabel(context.state.phase.title)
            }
        }
    }
}

private struct LockScreenDictationView: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.phase.symbolName)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sorla")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(state.phase.title)
                    .font(.headline)
            }
            Spacer()
            ElapsedTime(state: state)
            if state.phase.isCancellable {
                Button(intent: CancelDictationIntent()) {
                    Image(systemName: "xmark")
                        .accessibilityLabel("Cancel")
                }
            }
        }
    }
}

private struct ElapsedTime: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        if state.phase == .listening {
            Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .frame(maxWidth: 56)
        }
    }
}
