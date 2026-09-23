import AppKit
import Combine
import KeyboardShortcuts
import PrataCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var recordingController: RecordingController!
    private var appSettings: AppSettings!
    private var triggerMonitor: TriggerMonitor?
    private var settingsWindowController: SettingsWindowController?
    private var recordingIndicator: RecordingIndicatorPanel!
    private var feedbackSounds: FeedbackSoundPlayer!
    private var pendingStartSound: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.prata.app", category: "AppDelegate")
    private var modelSeparatorMenuItem: NSMenuItem!
    private var modelNotInstalledMenuItem: NSMenuItem!
    private var pasteLastMenuItem: NSMenuItem!
    private var triggerHintMenuItem: NSMenuItem!
    private var frontmostAppBeforeSettingsActivated: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()
    private var isModelReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appSettings = AppSettings()
        self.appSettings = appSettings

        recordingController = RecordingController(
            engine: ParakeetTranscriptionEngine(),
            modelName: PianissimoModel.displayName
        )
        recordingController.keepClipboardContent = appSettings.keepClipboardContent

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(isRecording: false)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let triggerHintItem = NSMenuItem(title: "", action: #selector(showSettings), keyEquivalent: "")
        menu.addItem(triggerHintItem)
        triggerHintMenuItem = triggerHintItem
        let pasteLastItem = NSMenuItem(title: "Paste Last Transcription", action: #selector(pasteLastTranscription), keyEquivalent: "")
        pasteLastItem.target = self
        pasteLastItem.setShortcut(for: .pasteLastTranscription)
        pasteLastItem.isEnabled = false
        menu.addItem(pasteLastItem)
        pasteLastMenuItem = pasteLastItem
        let modelSeparator = NSMenuItem.separator()
        menu.addItem(modelSeparator)
        modelSeparatorMenuItem = modelSeparator
        let modelNotInstalledItem = NSMenuItem(title: "Swedish model not installed", action: nil, keyEquivalent: "")
        modelNotInstalledItem.isEnabled = false
        menu.addItem(modelNotInstalledItem)
        modelNotInstalledMenuItem = modelNotInstalledItem
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Quit Prata", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        updateModelInstalledMenuItems()
        updateTriggerHintMenuItem()

        recordingIndicator = RecordingIndicatorPanel()
        feedbackSounds = FeedbackSoundPlayer()

        recordingController.onStateChange = { [weak self] isRecording in
            self?.updateIcon(isRecording: isRecording)
        }
        recordingController.onPhaseChange = { [weak self] phase in
            guard let indicator = self?.recordingIndicator else { return }
            switch phase {
            case .recording: indicator.showRecording()
            case .transcribing: indicator.showTranscribing()
            case .idle: indicator.hide()
            }
        }
        recordingController.onSpectrum = { [weak self] spectrum in
            self?.recordingIndicator.updateSpectrum(spectrum)
        }
        recordingController.onModelReadyChange = { [weak self] isReady in
            guard let self else { return }
            self.isModelReady = isReady
            self.updateIcon(isRecording: self.recordingController.isRecording)
        }

        let triggerMonitor = TriggerMonitor(
            onStart: { [weak self] in
                guard let self, self.recordingController.startRecording() else { return false }
                self.scheduleStartSound()
                return true
            },
            onFinish: { [weak self] in
                guard let self else { return }
                self.pendingStartSound?.cancel()
                guard self.recordingController.stopRecordingAndTranscribe() else { return }
                self.playStopSoundAfterTail()
            },
            onCancel: { [weak self] in
                self?.pendingStartSound?.cancel()
                self?.recordingController.cancelRecording()
            }
        )
        self.triggerMonitor = triggerMonitor
        triggerMonitor.configure(trigger: appSettings.triggerKey, mode: appSettings.recordingMode)

        KeyboardShortcuts.onKeyDown(for: .pasteLastTranscription) { [weak self] in
            MainActor.assumeIsolated {
                self?.recordingController.pasteLastTranscript()
            }
        }

        Publishers.CombineLatest(appSettings.$triggerKey, appSettings.$recordingMode)
            .dropFirst()
            .removeDuplicates(by: { $0.0 == $1.0 && $0.1 == $1.1 })
            .sink { [weak self] trigger, mode in
                self?.triggerMonitor?.configure(trigger: trigger, mode: mode)
                self?.updateTriggerHintMenuItem(trigger: trigger, mode: mode)
            }
            .store(in: &cancellables)

        appSettings.$keepClipboardContent
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] keepClipboardContent in
                self?.recordingController.keepClipboardContent = keepClipboardContent
            }
            .store(in: &cancellables)

        recordingController.prepare()

        Task {
            _ = await PermissionsManager.requestMicrophoneAccess()
            if !PermissionsManager.isAccessibilityTrusted() {
                PermissionsManager.promptAccessibilityIfNeeded()
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateModelInstalledMenuItems()
        updateTriggerHintMenuItem()
        pasteLastMenuItem.isEnabled = recordingController.lastTranscript != nil
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(appSettings: appSettings)
            controller.onKeyStateChange = { [weak self] isKey in
                self?.triggerMonitor?.isSuspended = isKey
                if isKey {
                    KeyboardShortcuts.disable(.pasteLastTranscription)
                } else {
                    KeyboardShortcuts.enable(.pasteLastTranscription)
                }
            }
            settingsWindowController = controller
        }
        frontmostAppBeforeSettingsActivated = NSWorkspace.shared.frontmostApplication
        settingsWindowController?.show()
    }

    // The status menu doesn't activate Prata, so it is only frontmost here when Settings is key.
    @objc private func pasteLastTranscription() {
        let ownPID = NSRunningApplication.current.processIdentifier
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ownPID else {
            recordingController.pasteLastTranscript()
            return
        }
        guard let previousApp = frontmostAppBeforeSettingsActivated,
              previousApp.processIdentifier != ownPID,
              !previousApp.isTerminated
        else {
            Self.logger.info("paste last skipped (no app to paste into)")
            return
        }
        recordingController.pasteLastTranscript {
            await Self.activate(previousApp, timeout: Self.activationTimeout)
        }
    }

    private static let activationTimeout: TimeInterval = 0.5

    private static func activate(_ app: NSRunningApplication, timeout: TimeInterval) async -> Bool {
        app.activate()
        let deadline = Date().addingTimeInterval(timeout)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    private func updateModelInstalledMenuItems() {
        let installed = PianissimoModel.isInstalled
        modelSeparatorMenuItem.isHidden = installed
        modelNotInstalledMenuItem.isHidden = installed
    }

    private func updateTriggerHintMenuItem(trigger: TriggerKey? = nil, mode: RecordingMode? = nil) {
        triggerHintMenuItem.title = TriggerHint.menuTitle(
            trigger: trigger ?? appSettings.triggerKey,
            mode: mode ?? appSettings.recordingMode,
            customShortcut: KeyboardShortcuts.getShortcut(for: .prataCustomTrigger)?.description
        )
    }

    // The mic keeps recording for the tail after release, so the chirp waits until it's closed.
    private func playStopSoundAfterTail() {
        guard appSettings.playSounds else { return }
        let delay = recordingController.tailDuration
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.feedbackSounds.playStop()
        }
    }

    // In push-to-talk a press only becomes a dictation after the minimum hold, so ⌘-shortcuts stay silent.
    private func scheduleStartSound() {
        pendingStartSound?.cancel()
        guard appSettings.playSounds else { return }
        let delay = appSettings.recordingMode == .pushToTalk ? PushToTalkGesture.defaultMinimumHold : 0
        pendingStartSound = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self, !Task.isCancelled, self.recordingController.isRecording else { return }
            self.feedbackSounds.playStart()
        }
    }

    private func updateIcon(isRecording: Bool) {
        let symbolName: String
        let description: String
        if !isModelReady {
            symbolName = "hourglass"
            description = "Prata (loading model)"
        } else if isRecording {
            symbolName = "mic.fill"
            description = "Prata (recording)"
        } else {
            symbolName = "mic"
            description = "Prata"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
