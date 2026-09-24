import AppKit
import KeyboardShortcuts
import os
import SorlaCore
import SwiftUI

// Set by the menu's "Check for Updates…" so Settings brings the Updates section into view.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var showsUpdates = false
}

struct SettingsView: View {
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var navigation: SettingsNavigation
    // Goes through the app's queue, which holds speech back while the microphone is recording.
    let announce: (String) -> Void
    @Environment(\.openURL) private var openURL
    @State private var isLaunchAtLoginEnabled = LoginItem.isEnabled
    @State private var loginItemRequiresApproval = LoginItem.requiresApproval
    @State private var customShortcutDescription = KeyboardShortcuts.getShortcut(for: .sorlaCustomTrigger)?.description
    @State private var isVoiceOverEnabled = NSWorkspace.shared.isVoiceOverEnabled

    static let windowTitle = String(localized: "Sorla Settings")

    private static let logger = Logger(subsystem: "com.sorla.app", category: "SettingsView")

    // The recorder's own 130 pt is too narrow for longer translations such as "Spela in kortkommando".
    private static let recorderWidth: CGFloat = 200

    private static let updatesSectionID = "updates"

    private static let keepLastTranscriptionDescription = String(localized: "Keeps your latest text in memory for up to five minutes so Paste Last Transcription can insert it again. Turning this off forgets it at once.")

    var body: some View {
        ScrollViewReader { proxy in
            form
                .onAppear { scrollToUpdatesIfAsked(proxy) }
                .onChange(of: navigation.showsUpdates) { scrollToUpdatesIfAsked(proxy) }
        }
    }

    private var form: some View {
        Form {
            Section {
                general
            }
            Section("Updates") {
                updates
            }
            .id(Self.updatesSectionID)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refreshLoginItemStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard (notification.object as? NSWindow)?.title == Self.windowTitle else { return }
            refreshLoginItemStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginItemStatus()
        }
        .onReceive(NSWorkspace.shared.publisher(for: \.isVoiceOverEnabled)) { enabled in
            isVoiceOverEnabled = enabled
        }
        .onChange(of: updateChecker.appStatus) { old, new in
            announceResult(of: "Sorla", wasChecking: old == .checking, row: UpdateRow.app(new))
        }
        .onChange(of: modelManager.status) { old, new in
            announceResult(of: String(localized: "Speech model"), wasChecking: old == .checking, row: UpdateRow.model(new))
        }
    }

    @ViewBuilder
    private var general: some View {
        Picker("Trigger", selection: $appSettings.triggerKey) {
            ForEach(TriggerKey.allCases, id: \.self) { trigger in
                Text(trigger.displayName).tag(trigger)
            }
        }

        if appSettings.triggerKey == .customShortcut {
            LabeledContent("Shortcut") {
                ShortcutField(name: .sorlaCustomTrigger, accessibilityLabel: String(localized: "Shortcut")) { shortcut in
                    MainActor.assumeIsolated {
                        customShortcutDescription = shortcut?.description
                    }
                }
                .frame(width: Self.recorderWidth)
            }
        }

        if appSettings.triggerKey == .fn {
            fnHint
        }

        Picker("Mode", selection: $appSettings.recordingMode) {
            ForEach(RecordingMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        Text(TriggerHint.explanation(
            trigger: appSettings.triggerKey,
            mode: appSettings.recordingMode,
            customShortcut: customShortcutDescription
        ))
        .font(.caption)
        .foregroundStyle(.secondary)

        LabeledContent("Model") {
            Text(LocalizedStringKey(PianissimoModel.displayName))
        }

        Toggle("Keep clipboard content", isOn: $appSettings.keepClipboardContent)

        Toggle("Play sounds", isOn: $appSettings.playSounds)

        // Without sight of the indicator, the sounds are how a VoiceOver user knows the microphone is on.
        if isVoiceOverEnabled {
            Text("The sounds tell you when recording starts and stops.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Toggle("Keep last transcription", isOn: $appSettings.keepLastTranscription)
            .help(Text(Self.keepLastTranscriptionDescription))
            .accessibilityHint(Text(Self.keepLastTranscriptionDescription))

        LabeledContent("Paste last transcription") {
            ShortcutField(name: .pasteLastTranscription, accessibilityLabel: String(localized: "Paste last transcription"))
                .frame(width: Self.recorderWidth)
        }
        .disabled(!appSettings.keepLastTranscription)

        Toggle("Launch at login", isOn: launchAtLoginBinding)

        if loginItemRequiresApproval {
            loginItemApprovalHint
        }
    }

    private func scrollToUpdatesIfAsked(_ proxy: ScrollViewProxy) {
        guard navigation.showsUpdates else { return }
        navigation.showsUpdates = false
        proxy.scrollTo(Self.updatesSectionID, anchor: .top)
    }

    // Only a check the user is watching in Settings is read out; a background one stays quiet.
    private func announceResult(of title: String, wasChecking: Bool, row: UpdateRow) {
        guard wasChecking, let text = row.text,
              NSApp.keyWindow?.title == Self.windowTitle
        else { return }
        announce("\(title): \(text)")
    }

    private func refreshLoginItemStatus() {
        isLaunchAtLoginEnabled = LoginItem.isEnabled
        loginItemRequiresApproval = LoginItem.requiresApproval
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { isLaunchAtLoginEnabled },
            set: { newValue in
                do {
                    try LoginItem.setEnabled(newValue)
                } catch {
                    Self.logger.error("failed to set launch at login to \(newValue, privacy: .public): \(String(describing: error), privacy: .public)")
                }
                isLaunchAtLoginEnabled = LoginItem.isEnabled
                loginItemRequiresApproval = LoginItem.requiresApproval
            }
        )
    }

    @ViewBuilder
    private var updates: some View {
        updateRow(
            title: Text(verbatim: "Sorla"),
            version: AppVersion.short,
            row: UpdateRow.app(updateChecker.appStatus),
            downloadLabel: Text("Download the new version of Sorla"),
            tryAgainLabel: Text("Try Again")
        ) {
            openURL(AppUpdateCheck.downloadPageURL)
        }
        updateRow(
            title: Text("Speech model"),
            version: modelManager.installedVersion,
            row: UpdateRow.model(modelManager.status),
            downloadLabel: Text("Download the speech model"),
            tryAgainLabel: Text("Try downloading the model again")
        ) {
            modelManager.downloadModel()
        }
        Toggle("Check for updates automatically", isOn: $appSettings.autoCheckUpdates)
        Toggle("Install updates automatically", isOn: $appSettings.autoInstallUpdates)
            .disabled(!appSettings.autoCheckUpdates)
        HStack {
            Spacer()
            Button("Check Now") { updateChecker.checkNow() }
                .accessibilityLabel(Text("Check for updates now"))
                .disabled(!UpdateRow.canCheckNow(app: updateChecker.appStatus, model: modelManager.status))
        }
    }

    // "Download" and "Try Again" alone don't say what they act on, so VoiceOver gets the full action.
    private func updateRow(
        title: Text,
        version: String?,
        row: UpdateRow,
        downloadLabel: Text,
        tryAgainLabel: Text,
        download: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text(verbatim: version ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    updateState(row)
                    switch row.action {
                    case .download:
                        Button("Download", action: download)
                            .accessibilityLabel(downloadLabel)
                    case .tryAgain:
                        Button("Try Again", action: download)
                            .accessibilityLabel(tryAgainLabel)
                    case nil:
                        EmptyView()
                    }
                }
                if row.kind == .failure, let text = row.text {
                    Text(text)
                        .font(.callout)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } label: {
            title
        }
    }

    @ViewBuilder
    private func updateState(_ row: UpdateRow) -> some View {
        switch row.kind {
        case .plain:
            if let text = row.text {
                Text(text).foregroundStyle(.secondary)
            }
        case .busy:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).accessibilityHidden(true)
                if let text = row.text { Text(text).foregroundStyle(.secondary) }
            }
        case .latest:
            Label(row.text ?? "", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .failure:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var fnHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pressing 🌐/Fn alone may also run the system's \"Press 🌐 key to\" action (change input source, emoji, or dictation). Set it to \"Do Nothing\" in Keyboard settings.")
                .font(.callout)
            Button("Open Keyboard Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private var loginItemApprovalHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sorla needs approval in Login Items to launch at login.")
                .font(.callout)
            Button("Open Login Items Settings…") {
                LoginItem.openSystemSettingsLoginItems()
            }
        }
    }
}
