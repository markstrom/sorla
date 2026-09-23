import AppKit
import Combine
import KeyboardShortcuts
import PrataCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var recordingController: RecordingController!
    private var appSettings: AppSettings!
    private var triggerMonitor: TriggerMonitor?
    private var settingsWindowController: SettingsWindowController?
    private var recordingIndicator: RecordingIndicatorPanel!
    private var modelMenuItems: [SpeechModel: NSMenuItem] = [:]
    private var pasteLastMenuItem: NSMenuItem!
    private var frontmostAppBeforeSettingsActivated: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()
    private let modelLoadingStatus = ModelLoadingStatus()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appSettings = AppSettings()
        self.appSettings = appSettings

        recordingController = RecordingController(
            engine: ParakeetTranscriptionEngine(model: appSettings.model),
            modelName: appSettings.model.displayName
        )
        recordingController.keepClipboardContent = appSettings.keepClipboardContent

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(isRecording: false)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        for model in SpeechModel.allCases {
            let item = NSMenuItem(
                title: model.displayName,
                action: #selector(selectModel(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = model
            modelMenuItems[model] = item
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let pasteLastItem = NSMenuItem(title: "Paste Last Transcription", action: #selector(pasteLastTranscription), keyEquivalent: "")
        pasteLastItem.target = self
        pasteLastItem.setShortcut(for: .pasteLastTranscription)
        pasteLastItem.isEnabled = false
        menu.addItem(pasteLastItem)
        pasteLastMenuItem = pasteLastItem
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Prata", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        updateModelMenuItems(selected: appSettings.model)

        recordingIndicator = RecordingIndicatorPanel()

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
            self.modelLoadingStatus.isModelReady = isReady
            self.updateIcon(isRecording: self.recordingController.isRecording)
        }

        let triggerMonitor = TriggerMonitor(
            onStart: { [weak self] in self?.recordingController.startRecording() ?? false },
            onFinish: { [weak self] in self?.recordingController.stopRecordingAndTranscribe() },
            onCancel: { [weak self] in self?.recordingController.cancelRecording() }
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
            }
            .store(in: &cancellables)

        appSettings.$model
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] model in
                guard let self else { return }
                self.recordingController.setEngine(ParakeetTranscriptionEngine(model: model), name: model.displayName)
                self.updateModelMenuItems(selected: model)
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
        updateModelMenuItems(selected: appSettings.model)
        pasteLastMenuItem.isEnabled = recordingController.lastTranscript != nil
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(appSettings: appSettings, modelLoadingStatus: modelLoadingStatus)
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
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ownPID,
              let previousApp = frontmostAppBeforeSettingsActivated,
              previousApp.processIdentifier != ownPID,
              !previousApp.isTerminated
        else {
            recordingController.pasteLastTranscript()
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

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? SpeechModel, model.isInstalled, model != appSettings.model else {
            return
        }
        appSettings.model = model
    }

    private func updateModelMenuItems(selected: SpeechModel) {
        for (model, item) in modelMenuItems {
            let installed = model.isInstalled
            item.isEnabled = installed
            item.state = model == selected ? .on : .off
            item.title = installed ? model.displayName : "\(model.displayName) – not installed"
        }
    }

    private func updateIcon(isRecording: Bool) {
        let symbolName: String
        let description: String
        if !modelLoadingStatus.isModelReady {
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
