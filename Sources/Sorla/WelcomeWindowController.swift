import AppKit
import SorlaCore
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    let state: WelcomeState
    private let appSettings: AppSettings
    private let modelManager: ModelManager
    private var permissionPoll: Timer?

    init(appSettings: AppSettings, modelManager: ModelManager, modelLoadingStatus: ModelLoadingStatus) {
        self.state = WelcomeState(modelLoadingStatus: modelLoadingStatus)
        self.appSettings = appSettings
        self.modelManager = modelManager

        let window = SorlaWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = WelcomeView.windowTitle
        window.isReleasedWhenClosed = false
        super.init(window: window)

        window.contentViewController = NSHostingController(rootView: WelcomeView(
            state: state,
            appSettings: appSettings,
            modelManager: modelManager,
            perform: { [weak self] action in self?.perform(action) },
            onDone: { [weak self] in self?.close() }
        ))
        window.center()
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    var isKey: Bool { window?.isKeyWindow ?? false }

    // Opened at launch or from the status menu: wait a turn, or macOS may leave the window behind others.
    func show() {
        startPollingPermissions()
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            window.orderFrontRegardless()
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        permissionPoll?.invalidate()
        permissionPoll = nil
        appSettings.hasCompletedOnboarding = true
    }

    // macOS doesn't notify about Accessibility changes, so the row polls while the window is open.
    private func startPollingPermissions() {
        state.refreshPermissions()
        guard permissionPoll == nil else { return }
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.state.refreshPermissions()
            }
        }
    }

    private func perform(_ action: WelcomeAction) {
        switch action {
        case .requestMicrophone:
            Task {
                _ = await PermissionsManager.requestMicrophoneAccess()
                state.refreshPermissions()
            }
        case .openMicrophoneSettings:
            if let url = SorlaIssue.microphoneAccessNeeded.settingsURL { NSWorkspace.shared.open(url) }
        case .openAccessibilitySettings:
            PermissionsManager.promptAccessibilityIfNeeded()
            if let url = SorlaIssue.accessibilityAccessNeeded.settingsURL { NSWorkspace.shared.open(url) }
        case .downloadModel:
            modelManager.downloadModel()
        case .reloadModel:
            modelManager.retryLoadingModel()
        }
    }
}
