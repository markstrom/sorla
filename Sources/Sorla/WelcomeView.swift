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

// Everything the page shows, as plain values, so it can be laid out in tests for any state.
struct WelcomeContent: Equatable {
    var microphone: WelcomeRowStatus
    var accessibility: WelcomeRowStatus
    var model: WelcomeRowStatus
    var isTextOnClipboard = false
    var isAccessibilityTrusted: Bool
    var readyLine: String
    var toggleModeTip: String?
    var isRecovery = false

    var isReady: Bool { WelcomeChecklist.isReady(microphone: microphone, accessibility: accessibility, model: model) }
    var readinessLine: String { isReady ? readyLine : WelcomeChecklist.notReadyLine }
    var pasteBlockedMessage: String? {
        WelcomeChecklist.pasteBlockedMessage(isTextOnClipboard: isTextOnClipboard, isAccessibilityTrusted: isAccessibilityTrusted)
    }
    var closeTitle: String { WelcomeChecklist.closeButtonTitle(isReady: isReady) }
}

struct WelcomeView: View {
    @ObservedObject var state: WelcomeState
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var modelManager: ModelManager
    let perform: (WelcomeAction) -> Void
    // Goes through the app's queue, which holds speech back while the microphone is recording.
    let announce: (String) -> Void
    let onDone: () -> Void

    static let windowTitle = String(localized: "Welcome to Sorla")
    static let recoveryWindowTitle = String(localized: "Set Up Sorla")

    var body: some View {
        WelcomePage(
            content: WelcomeContent(
                microphone: WelcomeChecklist.microphoneRow(state.microphone),
                accessibility: WelcomeChecklist.accessibilityRow(isTrusted: state.isAccessibilityTrusted),
                model: WelcomeChecklist.modelRow(
                    isInstalled: modelManager.isInstalled,
                    isLoaded: state.modelLoadingStatus == .ready,
                    loadFailed: state.modelLoadingStatus == .failed,
                    model: modelManager.status
                ),
                isTextOnClipboard: state.isTextOnClipboard,
                isAccessibilityTrusted: state.isAccessibilityTrusted,
                readyLine: WelcomeChecklist.readinessLine(
                    isReady: true,
                    trigger: appSettings.triggerKey,
                    mode: appSettings.recordingMode,
                    customShortcut: KeyboardShortcuts.getShortcut(for: .sorlaCustomTrigger)?.description
                ),
                toggleModeTip: WelcomeChecklist.toggleModeTip(mode: appSettings.recordingMode),
                isRecovery: state.isRecovery
            ),
            // The same stored choices as Settings › Updates; only the user's own click changes them (#73).
            autoCheckUpdates: $appSettings.autoCheckUpdates,
            autoInstallUpdates: $appSettings.autoInstallUpdates,
            perform: perform,
            announce: announce,
            onDone: onDone
        )
    }
}

struct WelcomePage: View {
    let content: WelcomeContent
    @Binding var autoCheckUpdates: Bool
    @Binding var autoInstallUpdates: Bool
    let perform: (WelcomeAction) -> Void
    let announce: (String) -> Void
    let onDone: () -> Void
    @State private var tryItText = ""
    @FocusState private var isTryItFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 540
    static let padding: CGFloat = 28
    static let markerWidth: CGFloat = 22
    static let columnSpacing: CGFloat = 12
    // A row's first line is as tall as its button, so title, button and marker share a centre line.
    static let rowLineHeight: CGFloat = 24
    // What a row's text keeps beside the widest button, in any language, before that button would have to shrink.
    static let minimumTextWidth: CGFloat = 220
    static var widestButtonAllowed: CGFloat {
        width - 2 * padding - markerWidth - 2 * columnSpacing - minimumTextWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            Text("Talk. Release. Done.")
                .font(.headline)
                .padding(.top, 8)

            if let message = content.pasteBlockedMessage {
                pasteBlocked(message)
                    .padding(.top, 20)
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 18) {
                row(.microphone, status: content.microphone)
                row(.accessibility, status: content.accessibility)
                row(.model, status: content.model)
            }
            .padding(.top, 24)

            Divider().padding(.vertical, 22)

            updates

            Divider().padding(.vertical, 22)

            tryIt
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        // Rows keep their size, so a change only fades; with Reduce Motion it happens at once.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: content)
        .onChange(of: content.isReady) { _, isReady in
            // The user may be in System Settings granting access, so the change is spoken rather than only shown.
            guard isReady else { return }
            isTryItFocused = true
            announce(content.readinessLine)
        }
    }

    private func pasteBlocked(_ message: String) -> some View {
        Label {
            // Room for either wording, so granting access while it shows doesn't move the rows.
            ZStack(alignment: .topLeading) {
                ForEach(Self.pasteBlockedMessages, id: \.self) { text in
                    Text(verbatim: text).fixedSize(horizontal: false, vertical: true).hidden().accessibilityHidden(true)
                }
                Text(verbatim: message).fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "doc.on.clipboard").accessibilityHidden(true)
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private static var pasteBlockedMessages: [String] {
        [false, true].compactMap { WelcomeChecklist.pasteBlockedMessage(isTextOnClipboard: true, isAccessibilityTrusted: $0) }
    }

    // Secondary to the checklist: the two switches from Settings › Updates, off until the user turns them on (#73).
    private var updates: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: WelcomeChecklist.updatesHeading)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            UpdateSwitch(title: SettingsRow.autoCheckUpdates.title, reason: WelcomeChecklist.autoCheckReason, isOn: $autoCheckUpdates)
            // As in Settings: installing needs the checks (c32ba97).
            UpdateSwitch(title: SettingsRow.autoInstallUpdates.title, reason: WelcomeChecklist.autoInstallReason, isOn: $autoInstallUpdates)
                .disabled(!autoCheckUpdates)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var tryIt: some View {
        // Room for both lines, so becoming ready doesn't move the field.
        ZStack {
            readiness(WelcomeChecklist.notReadyLine, isReady: false).hidden().accessibilityHidden(true)
            readiness(content.readyLine, isReady: true).hidden().accessibilityHidden(true)
            readiness(content.readinessLine, isReady: content.isReady)
        }
        .frame(maxWidth: .infinity)

        if let tip = content.toggleModeTip {
            Text(verbatim: tip)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }

        // Always there, so the user sees where to test; it only takes text once dictation can work.
        TextField("Try it here", text: $tryItText, axis: .vertical)
            .lineLimit(3...6)
            .textFieldStyle(.roundedBorder)
            .focused($isTryItFocused)
            .disabled(!content.isReady)
            .padding(.top, 12)
            .onAppear {
                // Opened for a blocked attempt, the user may still be typing elsewhere.
                if content.isReady, !content.isRecovery { isTryItFocused = true }
            }

        HStack {
            Spacer()
            let closeTitle = content.closeTitle
            // Return while typing in Try it here stays in the field; "Not now" has no Return, so a stray key doesn't close it.
            Button(closeTitle, action: onDone)
                .keyboardShortcut(content.isReady && !isTryItFocused ? .defaultAction : nil)
                .accessibilityInputLabels([Text(verbatim: closeTitle)])
        }
        .padding(.top, 16)
    }

    private func readiness(_ line: String, isReady: Bool) -> some View {
        Text(verbatim: line)
            .font(isReady ? .headline : .callout)
            .foregroundStyle(isReady ? .primary : .secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ row: WelcomeRow, status: WelcomeRowStatus) -> some View {
        let possible = row.possibleStatuses
        return HStack(alignment: .top, spacing: Self.columnSpacing) {
            marker(status)

            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: row.title)
                    .font(.body.bold())
                    .frame(minHeight: Self.rowLineHeight)
                // Room for the longest note the row can show, so a change of state doesn't move the rows below (#75).
                ZStack(alignment: .topLeading) {
                    ForEach(Self.unique(possible.map { $0.note ?? "" }), id: \.self) { note in
                        details(row, note: note).hidden().accessibilityHidden(true)
                    }
                    details(row, note: status.note)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(verbatim: status.accessibilityValue))

            // As wide as the widest button the row can show, so a checkmark turning into a button moves nothing.
            ZStack(alignment: .trailing) {
                ForEach(Self.unique(possible.compactMap(\.buttonTitle)), id: \.self) { title in
                    if let placeholder = possible.first(where: { $0.buttonTitle == title }) {
                        actionButton(placeholder).hidden().disabled(true).accessibilityHidden(true)
                    }
                }
                if status.buttonTitle != nil {
                    actionButton(status)
                }
            }
            .fixedSize()
            .frame(height: Self.rowLineHeight)
        }
        .accessibilityElement(children: .contain)
    }

    private func details(_ row: WelcomeRow, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: row.purpose)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note, !note.isEmpty {
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actionButton(_ status: WelcomeRowStatus) -> some View {
        let title = status.buttonTitle ?? ""
        let name = WelcomeChecklist.buttonName(status) ?? title
        return Button(title) {
            if case .needsAction(let action, _, _) = status { perform(action) }
        }
        .accessibilityLabel(Text(verbatim: name))
        // Voice Control users say what they see, so the visible title must still match.
        .accessibilityInputLabels([Text(verbatim: title), Text(verbatim: name)])
    }

    // Differs in shape as well as colour, for Differentiate Without Colour; VoiceOver hears the row's value instead.
    @ViewBuilder
    private func marker(_ status: WelcomeRowStatus) -> some View {
        Group {
            switch status {
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            case .needsAction:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            case .inProgress:
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: Self.markerWidth, height: Self.rowLineHeight)
        .accessibilityHidden(true)
    }

    private static func unique(_ strings: [String]) -> [String] {
        var seen = Set<String>()
        return strings.filter { seen.insert($0).inserted }
    }
}

// A switch with the setting's own title and one line on why to turn it on; greyed out with the switch when disabled.
private struct UpdateSwitch: View {
    let title: String
    let reason: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(alignment: .top, spacing: WelcomePage.columnSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                Text(verbatim: reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The switch carries both, so VoiceOver reads them once.
            .accessibilityHidden(true)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityHint(Text(verbatim: reason))
        }
    }
}
