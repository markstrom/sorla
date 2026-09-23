import AppKit
import PrataCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var recordingController: RecordingController!
    private var hotkeyController: HotkeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        recordingController = RecordingController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(isRecording: false)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Prata", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        recordingController.onStateChange = { [weak self] isRecording in
            self?.updateIcon(isRecording: isRecording)
        }

        hotkeyController = HotkeyController(
            onStart: { [weak self] in self?.recordingController.startRecording() },
            onStop: { [weak self] in self?.recordingController.stopRecordingAndTranscribe() }
        )

        recordingController.prepare()

        Task {
            _ = await PermissionsManager.requestMicrophoneAccess()
            if !PermissionsManager.isAccessibilityTrusted() {
                PermissionsManager.promptAccessibilityIfNeeded()
            }
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
