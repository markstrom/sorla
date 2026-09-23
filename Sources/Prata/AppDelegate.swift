import AppKit
import PrataCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let selectedModelDefaultsKey = "selectedModel"

    private var statusItem: NSStatusItem!
    private var recordingController: RecordingController!
    private var pushToTalkMonitor: RightCommandKeyMonitor?
    private var modelMenuItems: [SpeechModel: NSMenuItem] = [:]
    private var selectedModel: SpeechModel = .parakeet

    func applicationDidFinishLaunching(_ notification: Notification) {
        selectedModel = Self.loadSelectedModel()

        recordingController = RecordingController(
            engine: ParakeetTranscriptionEngine(model: selectedModel),
            modelName: selectedModel.displayName
        )

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

        pushToTalkMonitor = RightCommandKeyMonitor(
            onStart: { [weak self] in self?.recordingController.startRecording() },
            onFinish: { [weak self] in self?.recordingController.stopRecordingAndTranscribe() },
            onCancel: { [weak self] in self?.recordingController.cancelRecording() }
        )

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

    @objc @MainActor private func selectModel(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? SpeechModel, model.isInstalled, model != selectedModel else {
            return
        }
        selectedModel = model
        UserDefaults.standard.set(model.rawValue, forKey: Self.selectedModelDefaultsKey)
        recordingController.setEngine(ParakeetTranscriptionEngine(model: model), name: model.displayName)
        updateModelMenuItems()
    }

    private func updateModelMenuItems() {
        for (model, item) in modelMenuItems {
            let installed = model.isInstalled
            item.isEnabled = installed
            item.state = model == selectedModel ? .on : .off
            item.title = installed ? model.displayName : "\(model.displayName) – not installed"
        }
    }

    private static func loadSelectedModel() -> SpeechModel {
        guard
            let rawValue = UserDefaults.standard.string(forKey: selectedModelDefaultsKey),
            let saved = SpeechModel(rawValue: rawValue),
            saved.isInstalled
        else {
            return .parakeet
        }
        return saved
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
