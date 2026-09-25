import AppKit
import KeyboardShortcuts
import SorlaCore
import SwiftUI

@MainActor
final class WelcomeState: ObservableObject {
    @Published var microphone = PermissionsManager.microphoneAccess()
    @Published var isAccessibilityTrusted = PermissionsManager.isAccessibilityTrusted()
    @Published var modelLoadingStatus: ModelLoadingStatus
    @Published var isRecovery = false
    // Set when a blocked paste opened the window (#72); what it says depends on the text still being on the clipboard.
    @Published var blockedPaste: BlockedPaste? {
        didSet { refreshClipboard() }
    }
    @Published private(set) var isTextOnClipboard = false

    init(modelLoadingStatus: ModelLoadingStatus) {
        self.modelLoadingStatus = modelLoadingStatus
    }

    func refresh() {
        let microphone = PermissionsManager.microphoneAccess()
        if microphone != self.microphone { self.microphone = microphone }
        let isAccessibilityTrusted = PermissionsManager.isAccessibilityTrusted()
        if isAccessibilityTrusted != self.isAccessibilityTrusted { self.isAccessibilityTrusted = isAccessibilityTrusted }
        refreshClipboard()
    }

    // Copying something else takes the text off the clipboard, and then the window must stop saying it is there.
    private func refreshClipboard() {
        let isTextOnClipboard = blockedPaste?.isOnClipboard(changeCount: NSPasteboard.general.changeCount) ?? false
        if isTextOnClipboard != self.isTextOnClipboard { self.isTextOnClipboard = isTextOnClipboard }
    }
}

struct WelcomeView: View {
    @ObservedObject var state: WelcomeState
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var modelManager: ModelManager
    let perform: (WelcomeAction) -> Void
    let openUpdateSettings: () -> Void
    // Goes through the app's queue, which holds speech back while the microphone is recording.
    let announce: (String) -> Void
    let onDone: () -> Void
    @State private var tryItText = ""
    @FocusState private var isTryItFocused: Bool

    static let windowTitle = String(localized: "Welcome to Sorla")
    static let recoveryWindowTitle = String(localized: "Set Up Sorla")

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
        let readinessLine = WelcomeChecklist.readinessLine(
            isReady: isReady,
            trigger: appSettings.triggerKey,
            mode: appSettings.recordingMode,
            customShortcut: KeyboardShortcuts.getShortcut(for: .sorlaCustomTrigger)?.description
        )

        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            Text("Talk. Release. Done.").font(.headline)

            if let message = WelcomeChecklist.pasteBlockedMessage(isTextOnClipboard: state.isTextOnClipboard, isAccessibilityTrusted: state.isAccessibilityTrusted) {
                Label {
                    Text(verbatim: message).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "doc.on.clipboard").accessibilityHidden(true)
                }
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 14) {
                row(symbol: "mic.fill", title: Text("Microphone"), description: "So Sorla can hear you.", status: microphone)
                row(symbol: "accessibility", title: Text(verbatim: AccessibilityPaneName.current), description: "So Sorla can paste where you type.", status: accessibility)
                if !accessibility.isDone {
                    Text("If the switch is on but this doesn't show a checkmark, quit and reopen Sorla.")
                        .font(.callout)
                        .padding(.leading, 36)
                }
                row(symbol: "waveform", title: Text("Model"), description: LocalizedStringKey(PianissimoModel.displayName), status: model)
            }

            Divider()

            updates

            Divider()

            Text(readinessLine)
            .font(isReady ? .headline : .callout)
            .foregroundStyle(isReady ? .primary : .secondary)
            .multilineTextAlignment(.center)

            if let tip = WelcomeChecklist.toggleModeTip(mode: appSettings.recordingMode) {
                Text(tip)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Always there, so the user sees where to test; it only takes text once dictation can work.
            TextField("Try it here", text: $tryItText, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .focused($isTryItFocused)
                .disabled(!isReady)
                .onAppear {
                    // Opened for a blocked attempt, the user may still be typing elsewhere.
                    if isReady, !state.isRecovery { isTryItFocused = true }
                }

            HStack {
                Spacer()
                let closeTitle = WelcomeChecklist.closeButtonTitle(isReady: isReady)
                // Return while typing in Try it here stays in the field; "Not now" has no Return, so a stray key doesn't close it.
                Button(closeTitle, action: onDone)
                    .keyboardShortcut(isReady && !isTryItFocused ? .defaultAction : nil)
                    .accessibilityInputLabels([Text(verbatim: closeTitle)])
            }
        }
        .padding(24)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: isReady) { _, isReady in
            // The user may be in System Settings granting access, so the change is spoken rather than only shown.
            guard isReady else { return }
            isTryItFocused = true
            announce(readinessLine)
        }
    }

    // Secondary: says what the update toggles really do and leads to them, without changing either (#73).
    private var updates: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(verbatim: WelcomeChecklist.updatesNote(autoCheck: appSettings.autoCheckUpdates, autoInstall: appSettings.autoInstallUpdates))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(WelcomeChecklist.updateSettingsButtonTitle, action: openUpdateSettings)
                .accessibilityLabel(Text(verbatim: WelcomeChecklist.updateSettingsButtonName))
                .accessibilityInputLabels([Text(verbatim: WelcomeChecklist.updateSettingsButtonTitle), Text(verbatim: WelcomeChecklist.updateSettingsButtonName)])
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func row(symbol: String, title: Text, description: LocalizedStringKey, status: WelcomeRowStatus) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                title.font(.body.bold())
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
                    .accessibilityLabel(Text("Done"))
            case .inProgress:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("In progress"))
            case .needsAction(let action, let buttonTitle, _):
                Button(buttonTitle) { perform(action) }
                    .accessibilityLabel(Text(verbatim: WelcomeChecklist.buttonName(status) ?? buttonTitle))
                    // Voice Control users say what they see, so the visible title must still match.
                    .accessibilityInputLabels([Text(verbatim: buttonTitle), Text(verbatim: WelcomeChecklist.buttonName(status) ?? buttonTitle)])
            }
        }
        .accessibilityElement(children: .contain)
    }
}
