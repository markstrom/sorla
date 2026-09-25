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
    // What was dictated into Try it here. Emptied whenever the window opens or closes, so an old test isn't taken
    // for a new result and no dictated text stays on screen (#78).
    @Published var tryItText = ""
    // Set when a blocked paste opened the window (#72); what it says depends on whether Paste Last still has a text.
    @Published var isPasteBlocked = false {
        didSet { refreshTextKept() }
    }
    @Published private(set) var isTextKept = false
    private let hasKeptText: () -> Bool
    // The window's checks are the app's too: the menu bar icon's badge follows them (#76).
    var onPermissionsChange: (() -> Void)?

    init(modelLoadingStatus: ModelLoadingStatus, isTextKept: @escaping () -> Bool = { false }) {
        self.modelLoadingStatus = modelLoadingStatus
        self.hasKeptText = isTextKept
    }

    // Opened for a blocked dictation or paste it is the setup checklist rather than a welcome (#72).
    // Brought forward while already open, the field keeps what the user is testing.
    func willShow(forRecovery: Bool, isAlreadyOpen: Bool) {
        if forRecovery { isRecovery = true }
        if !isAlreadyOpen { tryItText = "" }
    }

    func didClose() {
        isRecovery = false
        isPasteBlocked = false
        tryItText = ""
    }

    func refresh() {
        let microphone = PermissionsManager.microphoneAccess()
        let isAccessibilityTrusted = PermissionsManager.isAccessibilityTrusted()
        let changed = microphone != self.microphone || isAccessibilityTrusted != self.isAccessibilityTrusted
        if microphone != self.microphone { self.microphone = microphone }
        if isAccessibilityTrusted != self.isAccessibilityTrusted { self.isAccessibilityTrusted = isAccessibilityTrusted }
        refreshTextKept()
        if changed { onPermissionsChange?() }
    }

    // Paste Last's expiry, a lock or the setting turned off end what Sorla keeps, and then the window says so.
    private func refreshTextKept() {
        let isTextKept = isPasteBlocked && hasKeptText()
        if isTextKept != self.isTextKept { self.isTextKept = isTextKept }
    }
}

// Everything the page shows, as plain values, so it can be laid out in tests for any state.
struct WelcomeContent: Equatable {
    var microphone: WelcomeRowStatus
    var accessibility: WelcomeRowStatus
    var model: WelcomeRowStatus
    var blockedPaste: BlockedPasteNote?
    var pasteLast: PasteLastRoute?
    var readyLine: String
    // The trigger as the ready line names it, set apart as a keycap.
    var readyKey: String?
    var toggleModeTip: String?
    var isRecovery = false

    var isReady: Bool { WelcomeChecklist.isReady(microphone: microphone, accessibility: accessibility, model: model) }
    var readinessLine: String { isReady ? readyLine : WelcomeChecklist.notReadyLine }
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
    // As in Settings: VoiceOver may take ⌃⌥V for itself, so the paste note names the menu item then (#64).
    @State private var isVoiceOverEnabled = NSWorkspace.shared.isVoiceOverEnabled

    static let windowTitle = String(localized: "Welcome to Sorla")
    static let recoveryWindowTitle = String(localized: "Set Up Sorla")

    var body: some View {
        let customShortcut = KeyboardShortcuts.getShortcut(for: .sorlaCustomTrigger)?.description
        let hasTrigger = appSettings.triggerKey != .customShortcut || !(customShortcut?.isEmpty ?? true)
        return WelcomePage(
            content: WelcomeContent(
                microphone: WelcomeChecklist.microphoneRow(state.microphone),
                accessibility: WelcomeChecklist.accessibilityRow(isTrusted: state.isAccessibilityTrusted),
                model: WelcomeChecklist.modelRow(
                    isInstalled: modelManager.isInstalled,
                    isLoaded: state.modelLoadingStatus == .ready,
                    loadFailed: state.modelLoadingStatus == .failed,
                    model: modelManager.status
                ),
                blockedPaste: state.isPasteBlocked ? BlockedPasteNote(isTextKept: state.isTextKept) : nil,
                pasteLast: PasteLastRoute.current(
                    shortcut: KeyboardShortcuts.getShortcut(for: .pasteLastTranscription)?.description,
                    isVoiceOverRunning: isVoiceOverEnabled
                ),
                readyLine: WelcomeChecklist.readinessLine(
                    isReady: true,
                    trigger: appSettings.triggerKey,
                    mode: appSettings.recordingMode,
                    customShortcut: customShortcut
                ),
                readyKey: hasTrigger ? TriggerHint.keyLabel(for: appSettings.triggerKey, customShortcut: customShortcut) : nil,
                toggleModeTip: WelcomeChecklist.toggleModeTip(mode: appSettings.recordingMode),
                isRecovery: state.isRecovery
            ),
            // The same stored choices as Settings › Updates; only the user's own click changes them (#73).
            autoCheckUpdates: $appSettings.autoCheckUpdates,
            autoInstallUpdates: $appSettings.autoInstallUpdates,
            perform: perform,
            tryItText: $state.tryItText,
            announce: announce,
            onDone: onDone
        )
        .onReceive(NSWorkspace.shared.publisher(for: \.isVoiceOverEnabled)) { enabled in
            isVoiceOverEnabled = enabled
        }
    }
}

struct WelcomePage: View {
    let content: WelcomeContent
    @Binding var autoCheckUpdates: Bool
    @Binding var autoInstallUpdates: Bool
    let perform: (WelcomeAction) -> Void
    var tryItText: Binding<String> = .constant("")
    let announce: (String) -> Void
    let onDone: () -> Void
    @FocusState private var isTryItFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 540
    static let padding: CGFloat = 28
    // The status marker, the same size and place on every row (#75); the regular spinner is this size too.
    static let markerSize: CGFloat = 32
    static let columnSpacing: CGFloat = 14
    static let rowSpacing: CGFloat = 20
    // What a row's text keeps beside the widest button, in any language, before that button would have to shrink.
    static let minimumTextWidth: CGFloat = 220
    static var widestButtonAllowed: CGFloat {
        width - 2 * padding - markerSize - 2 * columnSpacing - minimumTextWidth
    }
    static let statusFont = Font.callout

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            Text("Talk. Release. Done.")
                .font(.headline)
                .padding(.top, 8)

            if let note = content.blockedPaste {
                pasteBlocked(note)
                    .padding(.top, 20)
            }

            VStack(alignment: .leading, spacing: Self.rowSpacing) {
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

    private func pasteBlocked(_ note: BlockedPasteNote) -> some View {
        // Room for either wording, so the text expiring doesn't move the rows.
        ZStack(alignment: .topLeading) {
            ForEach(BlockedPasteNote.allCases, id: \.self) { other in
                pasteNote(other).hidden().accessibilityHidden(true)
            }
            pasteNote(note)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func pasteNote(_ note: BlockedPasteNote) -> some View {
        Label {
            Text(KeycapText.attributed(
                note.message(pasteLast: content.pasteLast),
                keys: [content.pasteLast?.keys],
                font: .system(.footnote, design: .monospaced)
            ))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "doc.text").accessibilityHidden(true)
        }
        .font(.callout)
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
        TextField("Try it here", text: tryItText, axis: .vertical)
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
        Text(KeycapText.attributed(line, keys: [content.readyKey], font: .system(.callout, design: .monospaced).weight(.semibold)))
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
                // Title and status beside the marker, so the state reads in words as well as colour and shape.
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.title)
                        .font(.body.bold())
                    // Room for the longest status the row can show, so a change of state moves nothing (#75).
                    ZStack(alignment: .topLeading) {
                        ForEach(Self.unique(possible.map(row.statusText)), id: \.self) { text in
                            statusLine(text).hidden()
                        }
                        statusLine(row.statusText(status))
                    }
                    // VoiceOver reads it as the row's value instead.
                    .accessibilityHidden(true)
                }
                .frame(minHeight: Self.markerSize, alignment: .leading)
                // Room for the longest note the row can show, so a change of state doesn't move the rows below (#75).
                ZStack(alignment: .topLeading) {
                    ForEach(Self.unique(possible.map { $0.note ?? "" }), id: \.self) { note in
                        details(row, note: note).hidden().accessibilityHidden(true)
                    }
                    details(row, note: status.note)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(verbatim: row.statusText(status)))

            // As wide as the widest button the row can show, so a checkmark turning into a button moves nothing.
            // The marker is only a picture; this button, beside it, is what acts.
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
            .frame(height: Self.markerSize)
        }
        .accessibilityElement(children: .contain)
    }

    private func statusLine(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Self.statusFont)
            .fixedSize(horizontal: false, vertical: true)
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

    // Differs in shape as well as colour, for Differentiate Without Colour, and the status text beside it says the
    // same in words; VoiceOver hears that as the row's value. Something in progress gets a spinner, never a cross.
    @ViewBuilder
    private func marker(_ status: WelcomeRowStatus) -> some View {
        Group {
            switch status {
            case .done:
                statusSymbol("checkmark.circle.fill", color: .green)
            case .needsAction:
                statusSymbol("xmark.circle.fill", color: .red)
            case .inProgress:
                ProgressView()
                    .controlSize(.regular)
            }
        }
        .frame(width: Self.markerSize, height: Self.markerSize)
        .accessibilityHidden(true)
    }

    private func statusSymbol(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, color)
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
