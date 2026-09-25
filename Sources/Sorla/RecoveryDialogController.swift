import AppKit
import SorlaCore
import SwiftUI

@MainActor
final class RecoveryDialogModel: ObservableObject {
    @Published private(set) var dialog: RecoveryDialog
    // Bumped on every show, also for the same dialog brought forward again or reopened after a close.
    @Published private(set) var presentation = 0
    @Published private(set) var isDefaultButtonArmed = false

    init(dialog: RecoveryDialog) {
        self.dialog = dialog
    }

    // Return is off the moment the dialog comes forward: a key typed then was meant for the app the user was in.
    func present(_ dialog: RecoveryDialog) {
        self.dialog = dialog
        presentation += 1
        isDefaultButtonArmed = false
    }

    // Only the latest presentation arms Return, once it has been on screen for the delay.
    func armDefaultButton(for presentation: Int, after delay: Duration, sleep: (Duration) async -> Void = { try? await Task.sleep(for: $0) }) async {
        await sleep(delay)
        guard !Task.isCancelled, presentation == self.presentation else { return }
        isDefaultButtonArmed = true
    }
}

// The microphone and restart dialogs (#72): in-app windows, never notifications, one at a time and reused.
@MainActor
final class RecoveryDialogController: NSWindowController, NSWindowDelegate {
    var onAction: ((RecoveryDialog.Action) -> Void)?
    // Whether the dialog's own action closed it; "Not now", Esc and the close button count as a "Not now".
    var onClose: ((RecoverySurface, _ byAction: Bool) -> Void)?
    private let model = RecoveryDialogModel(dialog: .microphoneStart)
    private var surface: RecoverySurface?
    private var isClosingByAction = false

    init() {
        let window = SorlaWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // VoiceOver reads the window's title first, so it is the dialog's; the content shows it as a heading.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        super.init(window: window)

        window.contentViewController = NSHostingController(rootView: RecoveryDialogView(
            model: model,
            perform: { [weak self] in self?.performAction() },
            notNow: { [weak self] in self?.close() }
        ))
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(_ dialog: RecoveryDialog, for surface: RecoverySurface) {
        // Another dialog in its place wasn't answered, so it isn't dismissed either.
        if let shown = self.surface, shown != surface, window?.isVisible == true {
            onClose?(shown, true)
        }
        self.surface = surface
        model.present(dialog)
        window?.title = dialog.title
        if window?.isVisible != true { window?.center() }
        (window as? SorlaWindow)?.present()
    }

    private func performAction() {
        let action = model.dialog.action
        isClosingByAction = true
        close()
        isClosingByAction = false
        onAction?(action)
    }

    func windowWillClose(_ notification: Notification) {
        guard let surface else { return }
        self.surface = nil
        onClose?(surface, isClosingByAction)
    }
}

struct RecoveryDialogView: View {
    @ObservedObject var model: RecoveryDialogModel
    let perform: () -> Void
    let notNow: () -> Void

    var body: some View {
        let dialog = model.dialog
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: dialog.title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: dialog.message)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                // Esc and ⌘. also close the window, as "Not now".
                Button(RecoveryDialog.notNow, action: notNow)
                    .accessibilityInputLabels([Text(verbatim: RecoveryDialog.notNow)])
                Button(dialog.actionTitle, action: perform)
                    .keyboardShortcut(model.isDefaultButtonArmed ? .defaultAction : nil)
                    .accessibilityInputLabels([Text(verbatim: dialog.actionTitle)])
            }
        }
        .padding(20)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        // Restarted on every presentation, not only when the wording changes.
        .task(id: model.presentation) {
            await model.armDefaultButton(for: model.presentation, after: RecoveryDialog.defaultButtonDelay)
        }
    }
}
