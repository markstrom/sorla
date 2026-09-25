import AppKit
import SorlaCore
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    let state: WelcomeState
    var onClose: (() -> Void)?
    private let appSettings: AppSettings
    private let modelManager: ModelManager
    private var permissionPoll: Timer?

    init(
        appSettings: AppSettings,
        modelManager: ModelManager,
        modelLoadingStatus: ModelLoadingStatus,
        isTextKept: @escaping () -> Bool,
        announce: @escaping (String) -> Void
    ) {
        self.state = WelcomeState(modelLoadingStatus: modelLoadingStatus, isTextKept: isTextKept)
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
            announce: announce,
            onDone: { [weak self] in self?.close() }
        ))
        window.center()
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    var isKey: Bool { window?.isKeyWindow ?? false }

    func show(forRecovery: Bool) {
        state.willShow(forRecovery: forRecovery, isAlreadyOpen: window?.isVisible == true)
        window?.title = state.isRecovery ? WelcomeView.recoveryWindowTitle : WelcomeView.windowTitle
        startPollingPermissions()
        (window as? SorlaWindow)?.present()
    }

    func windowWillClose(_ notification: Notification) {
        permissionPoll?.invalidate()
        permissionPoll = nil
        appSettings.hasCompletedOnboarding = true
        state.didClose()
        onClose?()
    }

    // macOS doesn't notify about Accessibility changes, so the row polls while the window is open.
    private func startPollingPermissions() {
        state.refresh()
        guard permissionPoll == nil else { return }
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.state.refresh()
            }
        }
    }

    private func perform(_ action: WelcomeAction) {
        switch action {
        case .requestMicrophone:
            Task {
                _ = await PermissionsManager.requestMicrophoneAccess()
                state.refresh()
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
