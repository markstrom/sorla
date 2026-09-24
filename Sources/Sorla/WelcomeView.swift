import AppKit
import KeyboardShortcuts
import SorlaCore
import SwiftUI

@MainActor
final class WelcomeState: ObservableObject {
    @Published var microphone = PermissionsManager.microphoneAccess()
    @Published var isAccessibilityTrusted = PermissionsManager.isAccessibilityTrusted()
    @Published var modelLoadingStatus: ModelLoadingStatus

    init(modelLoadingStatus: ModelLoadingStatus) {
        self.modelLoadingStatus = modelLoadingStatus
    }

    func refreshPermissions() {
        let microphone = PermissionsManager.microphoneAccess()
        if microphone != self.microphone { self.microphone = microphone }
        let isAccessibilityTrusted = PermissionsManager.isAccessibilityTrusted()
        if isAccessibilityTrusted != self.isAccessibilityTrusted { self.isAccessibilityTrusted = isAccessibilityTrusted }
    }
}

struct WelcomeView: View {
    @ObservedObject var state: WelcomeState
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var modelManager: ModelManager
    let perform: (WelcomeAction) -> Void
    let onDone: () -> Void
    @State private var tryItText = ""
    @FocusState private var isTryItFocused: Bool

    static let windowTitle = String(localized: "Welcome to Sorla")

    var body: some View {
        let microphone = WelcomeChecklist.microphoneRow(state.microphone)
        let accessibility = WelcomeChecklist.accessibilityRow(isTrusted: state.isAccessibilityTrusted)
        let model = WelcomeChecklist.modelRow(
            isInstalled: modelManager.isInstalled,
            isLoaded: state.modelLoadingStatus == .ready,
            loadFailed: state.modelLoadingStatus == .failed,
            model: modelManager.status
        )
        let isReady = WelcomeChecklist.isReady(microphone: microphone, accessibility: accessibility, model: model)

        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("Talk. Release. Done.").font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                row(symbol: "mic.fill", title: "Microphone", description: "So Sorla can hear you.", status: microphone)
                row(symbol: "accessibility", title: "Accessibility", description: "So Sorla can paste where you type.", status: accessibility)
                if !accessibility.isDone {
                    Text("If the switch is on but this doesn't turn green, quit and reopen Sorla.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 36)
                }
                row(symbol: "waveform", title: "Model", description: LocalizedStringKey(PianissimoModel.displayName), status: model)
            }

            Divider()

            Text(WelcomeChecklist.readinessLine(
                isReady: isReady,
                trigger: appSettings.triggerKey,
                mode: appSettings.recordingMode,
                customShortcut: KeyboardShortcuts.getShortcut(for: .sorlaCustomTrigger)?.description
            ))
            .font(isReady ? .headline : .callout)
            .foregroundStyle(isReady ? .primary : .secondary)
            .multilineTextAlignment(.center)

            if isReady {
                TextField("Try it here", text: $tryItText, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTryItFocused)
                    .onAppear { isTryItFocused = true }
            }

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func row(symbol: String, title: LocalizedStringKey, description: LocalizedStringKey, status: WelcomeRowStatus) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.bold())
                Text(description).font(.callout).foregroundStyle(.secondary)
                switch status {
                case .inProgress(let text), .needsAction(_, _, .some(let text)):
                    Text(text).font(.caption).foregroundStyle(.secondary)
                case .done, .needsAction(_, _, .none):
                    EmptyView()
                }
            }

            Spacer()

            switch status {
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            case .inProgress:
                ProgressView().controlSize(.small)
            case .needsAction(let action, let buttonTitle, _):
                Button(buttonTitle) { perform(action) }
            }
        }
    }
}
