import AppKit
import Combine
import KeyboardShortcuts
import SorlaCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var recordingController: RecordingController!
    private var modelManager: ModelManager!
    private var appSettings: AppSettings!
    private var triggerMonitor: TriggerMonitor?
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindowController: AboutWindowController?
    private var recordingIndicator: RecordingIndicatorPanel!
    private var feedbackSounds: FeedbackSoundPlayer!
    private var issueNotifier = IssueNotifier()
    private var pendingStartSound: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.sorla.app", category: "AppDelegate")
    private var statusMenuItem: NSMenuItem!
    private var statusMenuAction: MenuStatusAction?
    private var pasteLastMenuItem: NSMenuItem!
    private var triggerHintMenuItem: NSMenuItem!
    private var frontmostAppBeforeSettingsActivated: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()
    private var modelLoadingStatus: ModelLoadingStatus = .loading
    private var didNotifyModelNotReady = false
    private var isRefusedDictationHeld = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appSettings = AppSettings()
        self.appSettings = appSettings

        recordingController = RecordingController(
            engine: ParakeetTranscriptionEngine(),
            modelName: PianissimoModel.displayName
        )
        recordingController.keepClipboardContent = appSettings.keepClipboardContent

        modelManager = ModelManager(
            installer: ModelInstaller(
                modelsDirectory: PianissimoModel.modelsDirectory,
                network: URLSessionModelNetwork(),
                preparer: CoreMLModelPreparer()
            ),
            isDictationIdle: { [weak self] in self?.recordingController.phase == .idle },
            reloadModel: { [weak self] in await self?.recordingController.reloadModel() ?? false },
            automaticChecks: appSettings.autoCheckModelUpdates,
            automaticDownloads: appSettings.autoDownloadModelUpdates
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(isRecording: false)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let statusRowItem = NSMenuItem(title: "", action: #selector(performStatusAction), keyEquivalent: "")
        statusRowItem.target = self
        statusRowItem.isHidden = true
        menu.addItem(statusRowItem)
        statusMenuItem = statusRowItem
        let triggerHintItem = NSMenuItem(title: "", action: #selector(showSettings), keyEquivalent: "")
        menu.addItem(triggerHintItem)
        triggerHintMenuItem = triggerHintItem
        let pasteLastItem = NSMenuItem(title: "Paste Last Transcription", action: #selector(pasteLastTranscription), keyEquivalent: "")
        pasteLastItem.target = self
        pasteLastItem.setShortcut(for: .pasteLastTranscription)
        pasteLastItem.isEnabled = false
        menu.addItem(pasteLastItem)
        pasteLastMenuItem = pasteLastItem
        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About Sorla", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Quit Sorla", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        updateStatusMenuItem()
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
            guard let self, isReady else { return }
            self.modelLoadingStatus = .ready
            self.updateIcon(isRecording: self.recordingController.isRecording)
        }
        recordingController.onIssue = { [weak self] issue in
            self?.handleIssue(issue)
        }

        let triggerMonitor = TriggerMonitor(
            onStart: { [weak self] in
                guard let self else { return false }
                if let message = self.modelNotReadyMessage() {
                    guard DictationGate.waitsForRelease(mode: self.appSettings.recordingMode) else {
                        self.refuseDictation(message)
                        return false
                    }
                    self.isRefusedDictationHeld = true
                    return true
                }
                guard self.recordingController.startRecording() else { return false }
                self.scheduleStartSound()
                return true
            },
            onFinish: { [weak self] in
                guard let self else { return }
                if self.isRefusedDictationHeld {
                    self.isRefusedDictationHeld = false
                    if let message = self.modelNotReadyMessage() { self.refuseDictation(message) }
                    return
                }
                self.pendingStartSound?.cancel()
                guard self.recordingController.stopRecordingAndTranscribe() else { return }
                self.playStopSoundAfterTail()
            },
            onCancel: { [weak self] in
                self?.isRefusedDictationHeld = false
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

        modelManager.onInstalled = { [weak self] wasFirstInstall in
            guard let self, wasFirstInstall else { return }
            self.issueNotifier.post(TriggerHint.readyMessage(
                trigger: self.appSettings.triggerKey,
                mode: self.appSettings.recordingMode,
                customShortcut: KeyboardShortcuts.getShortcut(for: .sorlaCustomTrigger)?.description
            ))
        }
        modelManager.onFailure = { [weak self] issue in
            self?.handleIssue(issue)
        }
        modelManager.$status
            .removeDuplicates()
            .sink { [weak self] status in
                self?.modelStatusDidChange(status)
            }
            .store(in: &cancellables)

        appSettings.$autoCheckModelUpdates
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.modelManager.automaticChecks = enabled
            }
            .store(in: &cancellables)

        appSettings.$autoDownloadModelUpdates
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.modelManager.automaticDownloads = enabled
            }
            .store(in: &cancellables)

        modelManager.start()
        if modelManager.isInstalled {
            recordingController.prepare()
        }

        Task {
            _ = await PermissionsManager.requestMicrophoneAccess()
            if !PermissionsManager.isAccessibilityTrusted() {
                PermissionsManager.promptAccessibilityIfNeeded()
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateStatusMenuItem()
        updateTriggerHintMenuItem()
        pasteLastMenuItem.isEnabled = recordingController.lastTranscript != nil
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(appSettings: appSettings, modelManager: modelManager)
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

    @objc private func showAbout() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        aboutWindowController?.show()
    }

    @objc private func performStatusAction() {
        switch statusMenuAction {
        case .openMicrophoneSettings:
            if let url = SorlaIssue.microphoneAccessNeeded.settingsURL { NSWorkspace.shared.open(url) }
        case .openAccessibilitySettings:
            if let url = SorlaIssue.accessibilityAccessNeeded.settingsURL { NSWorkspace.shared.open(url) }
        case .downloadModel:
            modelManager.downloadModel()
        case .openSettings:
            showSettings()
        case nil:
            break
        }
    }

    // The status menu doesn't activate Sorla, so it is only frontmost here when Settings is key.
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

    // @Published fires before the property changes, so the status sink passes the new value in.
    private func updateStatusMenuItem(model: ModelStatus? = nil) {
        let row = MenuStatusRow.current(
            microphoneDenied: PermissionsManager.isMicrophoneAccessDenied(),
            accessibilityMissing: !PermissionsManager.isAccessibilityTrusted(),
            model: model ?? modelManager.status,
            modelLoadFailed: modelLoadingStatus == .failed
        )
        statusMenuAction = row?.action
        statusMenuItem.title = row?.title ?? ""
        statusMenuItem.isHidden = row == nil
    }

    private func modelStatusDidChange(_ status: ModelStatus) {
        if status.isBusy, !modelManager.isInstalled, modelLoadingStatus != .loading {
            modelLoadingStatus = .loading
            updateIcon(isRecording: recordingController.isRecording)
        }
        updateStatusMenuItem(model: status)
    }

    private func modelNotReadyMessage() -> String? {
        DictationGate.blockedMessage(isModelInstalled: modelManager.isInstalled, model: modelManager.status)
    }

    // The status row already shows the progress; the notification is only for the first refused attempt.
    private func refuseDictation(_ message: String) {
        Self.logger.info("dictation refused: model not installed yet")
        guard !didNotifyModelNotReady else { return }
        didNotifyModelNotReady = true
        issueNotifier.post(message)
    }

    private func handleIssue(_ issue: SorlaIssue) {
        if issue == .modelNotLoaded || (issue == .modelDownloadFailed && !modelManager.isInstalled) {
            modelLoadingStatus = .failed
            updateIcon(isRecording: recordingController.isRecording)
        }
        updateStatusMenuItem()
        issueNotifier.notify(issue)
    }

    private func updateTriggerHintMenuItem(trigger: TriggerKey? = nil, mode: RecordingMode? = nil) {
        triggerHintMenuItem.title = TriggerHint.menuTitle(
            trigger: trigger ?? appSettings.triggerKey,
            mode: mode ?? appSettings.recordingMode,
            customShortcut: KeyboardShortcuts.getShortcut(for: .sorlaCustomTrigger)?.description
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
        let icon = ModelLoadingStatus.menuBarIcon(for: modelLoadingStatus, isRecording: isRecording)
        statusItem.button?.image = NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: icon.accessibilityDescription)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
