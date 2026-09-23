import AppKit

// Mimics a menu item with a key equivalent, for keys NSMenuItem can't show (a lone right-hand modifier).
final class MenuShortcutRowView: NSView {
    static let leadingInset: CGFloat = 30
    static let trailingInset: CGFloat = 17
    static let rowHeight: CGFloat = 22
    private static let minimumGap: CGFloat = 24

    private let titleField = MenuShortcutRowView.label(color: .labelColor)
    private let keyField = MenuShortcutRowView.label(color: .secondaryLabelColor)

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: Self.rowHeight))
        autoresizingMask = [.width]
        addSubview(titleField)
        addSubview(keyField)
        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.leadingInset),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            keyField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trailingInset),
            keyField.centerYAnchor.constraint(equalTo: centerYAnchor),
            keyField.leadingAnchor.constraint(greaterThanOrEqualTo: titleField.trailingAnchor, constant: Self.minimumGap),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(title: String, key: String) {
        titleField.stringValue = title
        keyField.stringValue = key
        let width = Self.leadingInset + titleField.intrinsicContentSize.width + Self.minimumGap
            + keyField.intrinsicContentSize.width + Self.trailingInset
        setFrameSize(NSSize(width: max(frame.width, ceil(width)), height: Self.rowHeight))
    }

    private static func label(color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.menuFont(ofSize: 0)
        field.textColor = color
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }
}
