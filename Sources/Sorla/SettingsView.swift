import AppKit
import KeyboardShortcuts
import os
import SorlaCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var modelManager: ModelManager
    @State private var isLaunchAtLoginEnabled = LoginItem.isEnabled
    @State private var loginItemRequiresApproval = LoginItem.requiresApproval
    @State private var customShortcutDescription = KeyboardShortcuts.getShortcut(for: .sorlaCustomTrigger)?.description

    static let windowTitle = String(localized: "Sorla Settings")

    private static let logger = Logger(subsystem: "com.sorla.app", category: "SettingsView")

    var body: some View {
        Form {
            Picker("Trigger", selection: $appSettings.triggerKey) {
                ForEach(TriggerKey.allCases, id: \.self) { trigger in
                    Text(trigger.displayName).tag(trigger)
                }
            }

            if appSettings.triggerKey == .customShortcut {
                KeyboardShortcuts.Recorder("Shortcut", name: .sorlaCustomTrigger) { shortcut in
                    MainActor.assumeIsolated {
                        customShortcutDescription = shortcut?.description
                    }
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

            Picker("Model", selection: .constant(PianissimoModel.displayName)) {
                Text(LocalizedStringKey(PianissimoModel.displayName)).tag(PianissimoModel.displayName)
            }
            modelUpdates

            Toggle("Keep clipboard content", isOn: $appSettings.keepClipboardContent)

            Toggle("Play sounds", isOn: $appSettings.playSounds)

            KeyboardShortcuts.Recorder("Paste last transcription", name: .pasteLastTranscription)

            Toggle("Launch at login", isOn: launchAtLoginBinding)

            if loginItemRequiresApproval {
                loginItemApprovalHint
            }
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
    private var modelUpdates: some View {
        HStack {
            Text(modelManager.status.settingsText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            switch modelManager.status {
            case .updateAvailable:
                Button("Download") { modelManager.downloadModel() }
            case .failed, .notInstalled:
                Button("Try Again") { modelManager.downloadModel() }
            default:
                EmptyView()
            }
        }
        Toggle("Check for model updates automatically", isOn: $appSettings.autoCheckModelUpdates)
        Toggle("Download updates automatically", isOn: $appSettings.autoDownloadModelUpdates)
            .disabled(!appSettings.autoCheckModelUpdates)
        Button("Check Now") { modelManager.checkNow() }
            .disabled(modelManager.status.isBusy)
    }

    private var fnHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pressing 🌐/Fn alone may also run the system's \"Press 🌐 key to\" action (change input source, emoji, or dictation). Set it to \"Do Nothing\" in Keyboard settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Login Items Settings…") {
                LoginItem.openSystemSettingsLoginItems()
            }
        }
    }
}
