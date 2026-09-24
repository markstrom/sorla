import Accessibility
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
    private var updateChecker: UpdateChecker!
    private var appSettings: AppSettings!
    private var triggerMonitor: TriggerMonitor?
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindowController: AboutWindowController?
    private var welcomeWindowController: WelcomeWindowController?
    private var recordingIndicator: RecordingIndicatorPanel!
    private var feedbackSounds: FeedbackSoundPlayer!
    private var pendingStartSound: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.sorla.app", category: "AppDelegate")
    private var statusMenuItem: NSMenuItem!
    private var statusMenuAction: MenuStatusAction?
    private var pasteLastMenuItem: NSMenuItem!
    private var isSettingsKey = false
    private var triggerHintMenuItem: NSMenuItem!
    private var appBeforeSorlaActivated: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()
    private var modelLoadingStatus: ModelLoadingStatus = .loading {
        didSet { welcomeWindowController?.state.modelLoadingStatus = modelLoadingStatus }
    }
    private var transientStatus: TransientMenuStatus?
    private var isRefusedDictationHeld = false
    private var isStartingRecording = false
    private var startFailure: DictationCue?
    private var announcements = AnnouncementGate()
    private let recordingLimit = RecordingLimitWatch()

    // Opening Sorla again from Finder or Spotlight shows Settings, since the menu bar icon may be hidden behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            if try LegacyModelMigration.migrate(applicationSupport: PianissimoModel.applicationSupportDirectory) {
                Self.logger.info("moved the model from the legacy folder")
            }
        } catch {
            Self.logger.error("legacy model move failed: \(error.localizedDescription, privacy: .public)")
        }

        let appSettings = AppSettings()
        self.appSettings = appSettings

        recordingController = RecordingController(
            engine: ParakeetTranscriptionEngine(),
            modelName: PianissimoModel.displayName
        )
        recordingController.keepClipboardContent = appSettings.keepClipboardContent
        recordingController.keepsLastTranscript = appSettings.keepLastTranscription

        modelManager = ModelManager(
            installer: ModelInstaller(
                modelsDirectory: PianissimoModel.modelsDirectory,
                network: URLSessionModelNetwork(),
                preparer: CoreMLModelPreparer()
            ),
            isDictationIdle: { [weak self] in self?.recordingController.phase == .idle },
            reloadModel: { [weak self] in await self?.recordingController.reloadModel() ?? false },
            automaticChecks: appSettings.autoCheckUpdates,
            automaticDownloads: appSettings.autoInstallUpdates
        )
        updateChecker = UpdateChecker(
            currentVersion: AppVersion.short,
            source: URLSessionAppReleaseSource(appVersion: AppVersion.short ?? "dev"),
            automaticChecks: appSettings.autoCheckUpdates,
            checkModel: { [weak self] in
                // Before the first install the model row's own Download starts the large download instead.
                guard let modelManager = self?.modelManager, modelManager.isInstalled else { return }
                modelManager.checkNow()
            }
        )

        NSApp.mainMenu = MainMenu.make(target: self, about: #selector(showAbout), settings: #selector(showSettings))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let statusRowItem = NSMenuItem(title: "", action: #selector(performStatusAction), keyEquivalent: "")
        statusRowItem.target = self
        statusRowItem.isHidden = true
        menu.addItem(statusRowItem)
        statusMenuItem = statusRowItem
        let triggerHintItem = NSMenuItem(title: "", action: #selector(toggleDictation), keyEquivalent: "")
        triggerHintItem.target = self
        menu.addItem(triggerHintItem)
        triggerHintMenuItem = triggerHintItem
        let pasteLastItem = NSMenuItem(title: String(localized: "Paste Last Transcription"), action: #selector(pasteLastTranscription), keyEquivalent: "")
        pasteLastItem.target = self
        pasteLastItem.setShortcut(for: .pasteLastTranscription)
        pasteLastItem.isEnabled = false
        menu.addItem(pasteLastItem)
        pasteLastMenuItem = pasteLastItem
        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: String(localized: "About Sorla"), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        let updatesItem = NSMenuItem(title: String(localized: "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)
        let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: String(localized: "Quit Sorla"), action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        updateStatusMenuItem()
        updateTriggerHintMenuItem()

        recordingIndicator = RecordingIndicatorPanel()
        feedbackSounds = FeedbackSoundPlayer()

        recordingController.onStateChange = { [weak self] isRecording in
            self?.updateTriggerHintMenuItem()
            self?.watchRecordingLimit(isRecording: isRecording)
        }
        recordingController.onPhaseChange = { [weak self] phase in
            guard let self, let indicator = self.recordingIndicator else { return }
            switch phase {
            case .recording:
                self.transientStatus = nil
                indicator.showRecording()
            case .transcribing: indicator.showTranscribing()
            case .idle:
                indicator.hide()
            }
            self.updateIcon()
            self.updateStatusMenuItem()
        }
        recordingController.onSpectrum = { [weak self] spectrum in
            self?.recordingIndicator.updateSpectrum(spectrum)
        }
        recordingController.onMicrophoneMutedChange = { [weak self] isMuted in
            self?.recordingIndicator.setMicrophoneMuted(isMuted)
        }
        recordingController.onCue = { [weak self] cue in
            self?.presentCue(cue)
        }
        recordingController.onPaste = { [weak self] in
            // Only VoiceOver needs telling, and only that ⌘V was sent: that doesn't prove the text landed.
            guard NSWorkspace.shared.isVoiceOverEnabled else { return }
            self?.announce(String(localized: "Pasting text"))
        }
        recordingController.onMicrophoneClosed = { [weak self] in
            self?.postPendingAnnouncement()
        }
        recordingController.onModelReadyChange = { [weak self] isReady in
            guard let self else { return }
            self.modelLoadingStatus = isReady ? .ready : .loading
            self.updateIcon()
            self.updateStatusMenuItem()
        }
        recordingController.onIssue = { [weak self] issue in
            self?.handleIssue(issue)
        }

        let triggerMonitor = TriggerMonitor(
            onStart: { [weak self] in
                guard let self else { return false }
                self.startFailure = nil
                if let refusal = self.modelRefusal() {
                    return self.refuse(refusal)
                }
                self.isStartingRecording = true
                let started = self.recordingController.startRecording()
                self.isStartingRecording = false
                guard started else {
                    guard let failure = self.startFailure else { return false }
                    return self.refuse(failure)
                }
                // In push-to-talk a press only becomes a dictation after the minimum hold, so ⌘-shortcuts stay silent.
                self.scheduleStartSound(after: self.appSettings.recordingMode == .pushToTalk ? PushToTalkGesture.defaultMinimumHold : 0)
                return true
            },
            onFinish: { [weak self] in
                guard let self else { return }
                if self.isRefusedDictationHeld {
                    self.isRefusedDictationHeld = false
                    if let refusal = self.modelRefusal() ?? self.startFailure { self.refuseDictation(refusal) }
                    self.startFailure = nil
                    return
                }
                self.finishRecording()
            },
            onCancel: { [weak self] in
                self?.cancelRecording(announce: true)
            },
            onDiscard: { [weak self] in
                self?.cancelRecording(announce: false)
            }
        )
        self.triggerMonitor = triggerMonitor
        triggerMonitor.configure(trigger: appSettings.triggerKey, mode: appSettings.recordingMode)

        KeyboardShortcuts.onKeyDown(for: .pasteLastTranscription) { [weak self] in
            MainActor.assumeIsolated {
                Self.logger.info("paste-last shortcut pressed")
                self?.recordingController.pasteLastTranscript(after: {
                    await ModifierRelease.wait(isHeld: {
                        !NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
                    })
                })
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

        appSettings.$keepLastTranscription
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] keep in
                self?.keepLastTranscriptionDidChange(keep)
            }
            .store(in: &cancellables)
        updatePasteLastShortcut(keepLastTranscription: appSettings.keepLastTranscription)

        // Someone else at the Mac shouldn't be able to paste what was last dictated, or keep the microphone open.
        Publishers.MergeMany(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification),
            DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsLocked"))
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.endDictationAndForget()
        }
        .store(in: &cancellables)

        // Runs after the close, once the window is no longer visible.
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)
            .filter { $0.object is SorlaWindow }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.leaveIfNoWindowsAreLeft()
            }
            .store(in: &cancellables)

        modelManager.onFailure = { [weak self] issue in
            self?.handleIssue(issue)
        }
        modelManager.$status
            .removeDuplicates()
            .sink { [weak self] status in
                self?.modelStatusDidChange(status)
            }
            .store(in: &cancellables)

        updateChecker.$appStatus
            .removeDuplicates()
            .sink { [weak self] status in
                self?.updateStatusMenuItem(appStatus: status)
            }
            .store(in: &cancellables)

        appSettings.$autoCheckUpdates
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.updateChecker.automaticChecks = enabled
                self?.modelManager.automaticChecks = enabled
            }
            .store(in: &cancellables)

        appSettings.$autoInstallUpdates
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.modelManager.automaticDownloads = enabled
            }
            .store(in: &cancellables)

        modelManager.onAutomaticCheck = { [weak self] in
            self?.updateChecker.checkAppIfDue()
        }
        // Read before the app check stamps today's date, so the model's launch check is on the same daily schedule.
        let isCheckDue = updateChecker.isAutomaticCheckDue
        updateChecker.checkAppIfDue()
        modelManager.start(isCheckDue: isCheckDue)
        if modelManager.isInstalled {
            recordingController.prepare()
        }

        if WelcomeChecklist.shouldShow(
            hasCompletedOnboarding: appSettings.hasCompletedOnboarding,
            microphone: PermissionsManager.microphoneAccess(),
            isAccessibilityTrusted: PermissionsManager.isAccessibilityTrusted()
        ) {
            showWelcome()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateStatusMenuItem()
        updateTriggerHintMenuItem()
        pasteLastMenuItem.isEnabled = recordingController.lastTranscript() != nil
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(
                appSettings: appSettings,
                modelManager: modelManager,
                updateChecker: updateChecker,
                announce: { [weak self] text in self?.announce(text) }
            )
            controller.onKeyStateChange = { [weak self] isKey in
                guard let self else { return }
                self.triggerMonitor?.isSuspended = isKey
                self.isSettingsKey = isKey
                self.updatePasteLastShortcut()
            }
            settingsWindowController = controller
        }
        rememberFrontmostApp()
        settingsWindowController?.show()
    }

    private func showWelcome() {
        if welcomeWindowController == nil {
            welcomeWindowController = WelcomeWindowController(
                appSettings: appSettings,
                modelManager: modelManager,
                modelLoadingStatus: modelLoadingStatus
            )
        }
        rememberFrontmostApp()
        welcomeWindowController?.show()
    }

    // For people who can't use the trigger key; the menu doesn't take focus, so the text lands in the frontmost app.
    @objc private func toggleDictation() {
        if recordingController.isRecording {
            triggerMonitor?.recordingDidEndElsewhere()
            finishRecording()
            return
        }
        startFailure = nil
        if let refusal = modelRefusal() {
            refuseDictation(refusal)
            return
        }
        isStartingRecording = true
        let started = recordingController.startRecording()
        isStartingRecording = false
        guard started else {
            if let failure = startFailure { refuseDictation(failure) }
            startFailure = nil
            return
        }
        triggerMonitor?.recordingDidStartElsewhere()
        // Started while Settings or About is key: as with Paste Last, the text belongs in the app the user came from.
        if isSorlaWindowInFront { previousApp?.activate() }
        scheduleStartSound(after: 0)
    }

    private func watchRecordingLimit(isRecording: Bool) {
        guard isRecording else { return recordingLimit.stop() }
        recordingLimit.start(
            onWarning: { [weak self] in self?.recordingIndicator.setNearLimit(true) },
            onLimit: { [weak self] in self?.stopAtRecordingLimit() }
        )
    }

    private func stopAtRecordingLimit() {
        Self.logger.info("recording stopped at the length limit")
        triggerMonitor?.recordingDidEndElsewhere()
        finishRecording()
    }

    // The cue comes once the microphone is closed, so VoiceOver isn't recorded into anything.
    private func cancelRecording(announce: Bool) {
        let wasRecording = recordingController.isRecording
        isRefusedDictationHeld = false
        startFailure = nil
        pendingStartSound?.cancel()
        recordingController.cancelRecording()
        if announce, wasRecording {
            presentCue(.cancelled)
        }
    }

    private func finishRecording() {
        pendingStartSound?.cancel()
        guard recordingController.stopRecordingAndTranscribe() else { return }
        playStopSoundAfterTail()
    }

    @objc private func checkForUpdates() {
        showSettings()
        settingsWindowController?.revealUpdates()
        updateChecker.checkNow()
    }

    @objc private func showAbout() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        rememberFrontmostApp()
        aboutWindowController?.show()
    }

    @objc private func performStatusAction() {
        switch statusMenuAction {
        case .showWelcome:
            showWelcome()
        case .downloadModel:
            modelManager.downloadModel()
        case .downloadApp:
            NSWorkspace.shared.open(AppUpdateCheck.downloadPageURL)
        case .reloadModel:
            modelManager.retryLoadingModel()
        case .openSettings:
            showSettings()
        case .openSoundSettings:
            if let url = SorlaIssue.microphoneMuted.settingsURL { NSWorkspace.shared.open(url) }
        case .pasteLastTranscription where appSettings.keepLastTranscription:
            pasteLastTranscription()
        case .pasteLastTranscription:
            transientStatus = nil
            updateStatusMenuItem()
        case .dismiss:
            transientStatus = nil
            updateStatusMenuItem()
        case nil:
            break
        }
    }

    private func endDictationAndForget() {
        pendingStartSound?.cancel()
        isRefusedDictationHeld = false
        startFailure = nil
        triggerMonitor?.recordingDidEndElsewhere()
        recordingController.cancelRecording()
        recordingController.forgetLastTranscript()
        pasteLastMenuItem.isEnabled = false
        if transientStatus?.row.action == .pasteLastTranscription {
            transientStatus = nil
            updateStatusMenuItem()
        }
    }

    private func keepLastTranscriptionDidChange(_ keep: Bool) {
        recordingController.keepsLastTranscript = keep
        updatePasteLastShortcut(keepLastTranscription: keep)
        guard !keep else { return }
        pasteLastMenuItem.isEnabled = false
        if transientStatus?.row.action == .pasteLastTranscription {
            transientStatus = nil
            updateStatusMenuItem()
        }
    }

    // Off while Settings is key, where it could be recording a new shortcut, and while nothing is kept to paste.
    // @Published calls its sinks before the value changes, so the setting's sink passes the new value in.
    private func updatePasteLastShortcut(keepLastTranscription: Bool? = nil) {
        if keepLastTranscription ?? appSettings.keepLastTranscription, !isSettingsKey {
            KeyboardShortcuts.enable(.pasteLastTranscription)
        } else {
            KeyboardShortcuts.disable(.pasteLastTranscription)
        }
    }

    // The status menu doesn't activate Sorla, so it is only frontmost here when one of its windows is key.
    @objc private func pasteLastTranscription() {
        guard isSorlaWindowInFront else {
            recordingController.pasteLastTranscript()
            return
        }
        guard let previousApp else {
            Self.logger.info("paste last skipped (no app to paste into)")
            return
        }
        recordingController.pasteLastTranscript {
            await Self.activate(previousApp, timeout: Self.activationTimeout) ? .ready : .abandoned
        }
    }

    private static let activationTimeout: TimeInterval = 0.5

    // The Welcome window's Try it here field is the one Sorla window worth pasting into.
    private var isSorlaWindowInFront: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier
            && welcomeWindowController?.isKey != true
    }

    private var previousApp: NSRunningApplication? {
        guard let app = appBeforeSorlaActivated, !app.isTerminated else { return nil }
        return app
    }

    private func rememberFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != NSRunningApplication.current.processIdentifier
        else { return }
        appBeforeSorlaActivated = app
    }

    // With no window left Sorla shouldn't stay active, or a ⌘Q meant for the next app would quit Sorla.
    private func leaveIfNoWindowsAreLeft() {
        guard NSApp.isActive, !NSApp.windows.contains(where: { $0 is SorlaWindow && $0.isVisible }) else { return }
        if let previousApp {
            previousApp.activate()
        } else {
            NSApp.deactivate()
        }
    }

    private static func activate(_ app: NSRunningApplication, timeout: TimeInterval) async -> Bool {
        app.activate()
        let deadline = Date().addingTimeInterval(timeout)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    // @Published fires before the property changes, so the status sinks pass the new value in.
    private func updateStatusMenuItem(model: ModelStatus? = nil, appStatus: AppUpdateStatus? = nil) {
        let now = Date()
        if transientStatus?.isExpired(at: now) == true { transientStatus = nil }
        let row = MenuStatusRow.current(
            microphoneDenied: PermissionsManager.isMicrophoneAccessDenied(),
            accessibilityMissing: !PermissionsManager.isAccessibilityTrusted(),
            model: model ?? modelManager.status,
            modelLoadFailed: modelManager.isInstalled && modelLoadingStatus == .failed,
            modelLoading: modelManager.isInstalled && modelLoadingStatus == .loading,
            transient: transientStatus,
            appUpdate: (appStatus ?? updateChecker.appStatus).availableVersion,
            now: now
        )
        statusMenuAction = row?.action
        statusMenuItem.title = row?.title ?? ""
        statusMenuItem.isHidden = row == nil
    }

    private func modelStatusDidChange(_ status: ModelStatus) {
        if status.isBusy, !modelManager.isInstalled, modelLoadingStatus != .loading {
            modelLoadingStatus = .loading
            updateIcon()
        }
        updateStatusMenuItem(model: status)
    }

    private func modelRefusal() -> DictationCue? {
        DictationGate.refusal(
            isModelInstalled: modelManager.isInstalled,
            isModelLoading: modelLoadingStatus == .loading,
            didModelFailToLoad: modelLoadingStatus == .failed,
            model: modelManager.status
        )
    }

    // A push-to-talk press may still become a ⌘-shortcut, so its refusal waits for the release.
    private func refuse(_ refusal: DictationCue) -> Bool {
        guard DictationGate.waitsForRelease(mode: appSettings.recordingMode) else {
            refuseDictation(refusal)
            return false
        }
        isRefusedDictationHeld = true
        return true
    }

    private func refuseDictation(_ refusal: DictationCue) {
        Self.logger.info("dictation refused: \(refusal.symbolName, privacy: .public)")
        presentCue(refusal)
    }

    private func handleIssue(_ issue: SorlaIssue) {
        if issue == .modelNotLoaded || (issue == .modelDownloadFailed && !modelManager.isInstalled) {
            modelLoadingStatus = .failed
            updateIcon()
        }
        if let transient = TransientMenuStatus(issue: issue, at: Date()) {
            transientStatus = transient
        }
        if let cue = DictationCue(issue: issue) {
            if isStartingRecording {
                startFailure = cue
            } else {
                // Paste Last needs Accessibility too, so without it only ⌘V works.
                presentCue(cue, pasteShortcut: issue == .accessibilityAccessNeeded ? nil : currentPasteShortcut)
            }
        }
        updateStatusMenuItem()
    }

    // Without a kept transcription the text on the clipboard is only reachable with ⌘V.
    private var currentPasteShortcut: String? {
        guard appSettings.keepLastTranscription else { return nil }
        return KeyboardShortcuts.getShortcut(for: .pasteLastTranscription)?.description
    }

    private func presentCue(_ cue: DictationCue) {
        presentCue(cue, pasteShortcut: currentPasteShortcut)
    }

    private func presentCue(_ cue: DictationCue, pasteShortcut: String?) {
        let text = cue.announcement(pasteShortcut: pasteShortcut)
        if let issue = cue.issue(pasteShortcut: pasteShortcut), let transient = TransientMenuStatus(issue: issue, at: Date()) {
            transientStatus = transient
            updateStatusMenuItem()
        }
        // A newer recording owns the indicator.
        if !recordingController.isRecording {
            recordingIndicator.showCue(symbolName: cue.symbolName, label: text)
        }
        announce(text)
    }

    private func announce(_ text: String) {
        guard let text = announcements.request(text, isMicrophoneOpen: recordingController.isMicrophoneOpen) else { return }
        AccessibilityNotification.Announcement(text).post()
    }

    private func postPendingAnnouncement() {
        guard let text = announcements.microphoneClosed() else { return }
        AccessibilityNotification.Announcement(text).post()
    }

    private func updateTriggerHintMenuItem(trigger: TriggerKey? = nil, mode: RecordingMode? = nil) {
        triggerHintMenuItem.title = TriggerHint.menuTitle(
            trigger: trigger ?? appSettings.triggerKey,
            mode: mode ?? appSettings.recordingMode,
            customShortcut: KeyboardShortcuts.getShortcut(for: .sorlaCustomTrigger)?.description,
            isRecording: recordingController.isRecording
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

    private func scheduleStartSound(after delay: TimeInterval) {
        pendingStartSound?.cancel()
        guard appSettings.playSounds else { return }
        pendingStartSound = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self, !Task.isCancelled, self.recordingController.isRecording else { return }
            self.feedbackSounds.playStart()
        }
    }

    private func updateIcon() {
        let icon = ModelLoadingStatus.menuBarIcon(for: modelLoadingStatus, phase: recordingController.phase)
        statusItem.button?.image = icon.glyph.image(accessibilityDescription: icon.accessibilityDescription)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
