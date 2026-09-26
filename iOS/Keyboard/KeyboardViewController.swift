import UIKit

// The Sorla keyboard's only job: put the finished transcript into the focused text field. It holds no model and
// records no audio; the Sorla app does both and hands the text over through the App Group (TranscriptHandoff).
// A status line shows what Sorla is doing, and globe, space, delete and return keep the keyboard usable on its own.
final class KeyboardViewController: UIInputViewController {
    private let strings = KeyboardStrings.current
    private let statusLabel = UILabel()
    private let fullAccessLabel = UILabel()
    private var nextKeyboardButton: UIButton!
    private var store: TranscriptHandoffStore?
    private var observer: DarwinNotificationObserver?
    // "Infogat" stays until Sorla starts the next dictation.
    private var hasInserted = false
    private var shownStatus: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        observer = DarwinNotificationObserver(
            names: [TranscriptHandoff.transcriptReadyNotification, TranscriptHandoff.phaseChangedNotification]
        ) { [weak self] in
            self?.refresh()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    override func viewWillLayoutSubviews() {
        nextKeyboardButton.isHidden = !needsInputModeSwitchKey
        super.viewWillLayoutSubviews()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refresh()
    }

    // Inserts a waiting transcript (once, and only into the field that is focused now), then updates the status line.
    private func refresh() {
        guard hasFullAccess else {
            fullAccessLabel.isHidden = false
            show(strings.idle)
            return
        }
        fullAccessLabel.isHidden = true
        if store == nil {
            store = TranscriptHandoffStore.shared()
        }
        guard let store else {
            show(strings.idle)
            return
        }
        if let delivery = store.claimPendingDelivery() {
            textDocumentProxy.insertText(delivery.text)
            hasInserted = true
            UIAccessibility.post(notification: .announcement, argument: strings.inserted)
        }
        let phase = store.phase
        if phase != .idle {
            hasInserted = false
        }
        show(phase == .idle && hasInserted ? strings.inserted : strings.status(for: phase))
    }

    private func show(_ status: String) {
        guard status != shownStatus else { return }
        shownStatus = status
        statusLabel.text = status
    }

    // MARK: Layout

    private func buildLayout() {
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.textColor = .label
        statusLabel.accessibilityTraits.insert(.updatesFrequently)

        fullAccessLabel.text = strings.fullAccessNeeded
        fullAccessLabel.font = .preferredFont(forTextStyle: .footnote)
        fullAccessLabel.adjustsFontForContentSizeCategory = true
        fullAccessLabel.numberOfLines = 0
        fullAccessLabel.textAlignment = .center
        fullAccessLabel.textColor = .secondaryLabel
        fullAccessLabel.isHidden = true

        nextKeyboardButton = key(systemImage: "globe", label: strings.nextKeyboard)
        // Tap for the next keyboard, touch and hold for the list, as the system keyboards do.
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let space = key(title: strings.space, label: strings.space)
        space.addAction(UIAction { [weak self] _ in self?.textDocumentProxy.insertText(" ") }, for: .touchUpInside)

        let delete = key(systemImage: "delete.left", label: strings.delete)
        delete.addAction(UIAction { [weak self] _ in self?.textDocumentProxy.deleteBackward() }, for: .touchUpInside)

        let returnKey = key(title: strings.returnKey, label: strings.returnKey)
        returnKey.addAction(UIAction { [weak self] _ in self?.textDocumentProxy.insertText("\n") }, for: .touchUpInside)

        let keys = UIStackView(arrangedSubviews: [nextKeyboardButton, space, delete, returnKey])
        keys.axis = .horizontal
        keys.spacing = 6
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for fixed in [nextKeyboardButton!, delete, returnKey] {
            fixed.setContentHuggingPriority(.required, for: .horizontal)
            fixed.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        }

        let column = UIStackView(arrangedSubviews: [statusLabel, fullAccessLabel, keys])
        column.axis = .vertical
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            column.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            column.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    private func key(title: String? = nil, systemImage: String? = nil, label: String) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
        }
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .medium
        configuration.title = title // the configuration's title font follows Dynamic Type
        if let systemImage {
            configuration.image = UIImage(systemName: systemImage)
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .body)
        }
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = label
        button.accessibilityTraits.insert(.keyboardKey)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return button
    }
}
