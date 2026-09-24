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
    @ObservedObject var appUpdater: AppUpdater
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
    private static var maxHeight: CGFloat { max(360, (NSScreen.main?.visibleFrame.height ?? 800) - 80) }

    private static let updatesSectionID = "updates"

    private static let keepLastTranscriptionDescription = String(localized: "Keeps your latest text in memory for up to five minutes so you can paste it again with Paste Last Transcription. Turning this off forgets it at once.")

    var body: some View {
        ScrollViewReader { proxy in
            form
                .onAppear { scrollToUpdatesIfAsked(proxy) }
                .onChange(of: navigation.showsUpdates) { scrollToUpdatesIfAsked(proxy) }
        }
    }

    private var form: some View {
        Form {
            Section("Dictation") {
                dictation
            }
            Section("Pasting") {
                pasting
            }
            Section("General") {
                general
            }
            Section("Updates") {
                updates
            }
            .id(Self.updatesSectionID)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        // Never taller than the screen: the form scrolls instead of pushing rows off the bottom.
        .frame(maxHeight: Self.maxHeight)
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
            announceResult(of: SettingsRow.appUpdates.title, wasChecking: old == .checking, row: UpdateRow.app(new, offer: appOffer(status: new)))
        }
        .onChange(of: modelManager.status) { old, new in
            announceResult(of: SettingsRow.speechModel.title, wasChecking: old == .checking, row: UpdateRow.model(new))
        }
    }

    @ViewBuilder
    private var dictation: some View {
        Picker(SettingsRow.trigger.title, selection: $appSettings.triggerKey) {
            ForEach(TriggerKey.allCases, id: \.self) { trigger in
                Text(trigger.displayName).tag(trigger)
            }
        }

        if appSettings.triggerKey == .customShortcut {
            LabeledContent(SettingsRow.customShortcut.title) {
                ShortcutField(name: .sorlaCustomTrigger, row: .customShortcut) { shortcut in
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

        Picker(SettingsRow.mode.title, selection: $appSettings.recordingMode) {
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

        LabeledContent(SettingsRow.model.title) {
            Text(LocalizedStringKey(PianissimoModel.displayName))
        }
    }

    @ViewBuilder
    private var pasting: some View {
        Toggle(SettingsRow.keepClipboardContent.title, isOn: $appSettings.keepClipboardContent)
        Text("Sorla borrows the clipboard to paste, then puts back what was there.")
            .font(.caption)
            .foregroundStyle(.secondary)

        Toggle(SettingsRow.keepLastTranscription.title, isOn: $appSettings.keepLastTranscription)
            .help(Text(Self.keepLastTranscriptionDescription))
            .accessibilityHint(Text(Self.keepLastTranscriptionDescription))

        LabeledContent(SettingsRow.pasteLastShortcut.title) {
            ShortcutField(name: .pasteLastTranscription, row: .pasteLastShortcut)
                .frame(width: Self.recorderWidth)
        }
        .disabled(!appSettings.keepLastTranscription)
    }

    @ViewBuilder
    private var general: some View {
        Toggle(SettingsRow.playSounds.title, isOn: $appSettings.playSounds)

        // Without sight of the indicator, the sounds are how a VoiceOver user knows the microphone is on.
        if isVoiceOverEnabled {
            Text("The sounds tell you when recording starts and stops.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Toggle(SettingsRow.launchAtLogin.title, isOn: launchAtLoginBinding)

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

    private func appOffer(status: AppUpdateStatus) -> AppUpdateOffer? {
        AppUpdateOffer.make(status: status, pin: updateChecker.pinnedRelease, install: appUpdater.state, location: appUpdater.location)
    }

    @ViewBuilder
    private var updates: some View {
        updateRow(
            .appUpdates,
            version: AppVersion.short,
            row: UpdateRow.app(updateChecker.appStatus, offer: appOffer(status: updateChecker.appStatus)),
            downloadLabel: Text("Download the new version of Sorla"),
            tryAgainLabel: Text("Try Again"),
            install: {
                if let pin = updateChecker.pinnedRelease { appUpdater.install(pin) }
            }
        ) {
            openURL(AppUpdateCheck.downloadPageURL)
        }
        updateRow(
            .speechModel,
            version: modelManager.installedVersion,
            row: UpdateRow.model(modelManager.status),
            downloadLabel: Text("Download the speech model"),
            tryAgainLabel: Text("Try downloading the model again")
        ) {
            modelManager.downloadModel()
        }
        Toggle(SettingsRow.autoCheckUpdates.title, isOn: $appSettings.autoCheckUpdates)
        Toggle(SettingsRow.autoInstallUpdates.title, isOn: $appSettings.autoInstallUpdates)
            .disabled(!appSettings.autoCheckUpdates)
        Text("Downloads new versions of Sorla and the speech model in the background. Sorla installs its update once you haven't dictated for 10 minutes, or at its next launch, and restarts by itself.")
            .font(.caption)
            .foregroundStyle(.secondary)
        HStack {
            Spacer()
            Button("Check Now") { updateChecker.checkNow() }
                .accessibilityLabel(Text("Check for updates now"))
                .disabled(!UpdateRow.canCheckNow(app: updateChecker.appStatus, model: modelManager.status, install: appUpdater.state))
        }
    }

    // "Download" and "Try Again" alone don't say what they act on, so VoiceOver gets the full action.
    private func updateRow(
        _ settingsRow: SettingsRow,
        version: String?,
        row: UpdateRow,
        downloadLabel: Text,
        tryAgainLabel: Text,
        install: @escaping () -> Void = {},
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
                    case .install:
                        Button("Install and Relaunch", action: install)
                            .accessibilityLabel(Text("Install Sorla and relaunch it"))
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
                if let note = row.note {
                    Text(note)
                        .font(.callout)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        } label: {
            Text(verbatim: settingsRow.title)
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
