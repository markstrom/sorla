import AppKit
import Combine
import PrataCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var recordingController: RecordingController!
    private var appSettings: AppSettings!
    private var triggerMonitor: TriggerMonitor?
    private var modelMenuItems: [SpeechModel: NSMenuItem] = [:]
    private var cancellables = Set<AnyCancellable>()

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
        menu.addItem(NSMenuItem(title: "Quit Prata", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        updateModelMenuItems()

        recordingController.onStateChange = { [weak self] isRecording in
            self?.updateIcon(isRecording: isRecording)
        }

        let triggerMonitor = TriggerMonitor(
            onStart: { [weak self] in self?.recordingController.startRecording() },
            onFinish: { [weak self] in self?.recordingController.stopRecordingAndTranscribe() },
            onCancel: { [weak self] in self?.recordingController.cancelRecording() }
        )
        self.triggerMonitor = triggerMonitor
        triggerMonitor.configure(trigger: appSettings.triggerKey, mode: appSettings.recordingMode)

        Publishers.CombineLatest(appSettings.$triggerKey, appSettings.$recordingMode)
            .dropFirst()
            .sink { [weak self] trigger, mode in
                self?.triggerMonitor?.configure(trigger: trigger, mode: mode)
            }
            .store(in: &cancellables)

        appSettings.$model
            .dropFirst()
            .sink { [weak self] model in
                guard let self else { return }
                self.recordingController.setEngine(ParakeetTranscriptionEngine(model: model), name: model.displayName)
                self.updateModelMenuItems()
            }
            .store(in: &cancellables)

        appSettings.$keepClipboardContent
            .dropFirst()
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
        updateModelMenuItems()
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? SpeechModel, model.isInstalled, model != appSettings.model else {
            return
        }
        appSettings.model = model
    }

    private func updateModelMenuItems() {
        for (model, item) in modelMenuItems {
            let installed = model.isInstalled
            item.isEnabled = installed
            item.state = model == appSettings.model ? .on : .off
            item.title = installed ? model.displayName : "\(model.displayName) – not installed"
        }
    }

    private func updateIcon(isRecording: Bool) {
        let symbolName = isRecording ? "mic.fill" : "mic"
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: isRecording ? "Prata (recording)" : "Prata"
        )
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
