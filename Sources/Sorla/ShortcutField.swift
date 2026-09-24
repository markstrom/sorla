import AppKit
import KeyboardShortcuts
import SwiftUI

// KeyboardShortcuts' recorder fixes its width at 130 pt; this lets Settings size it so longer translations fit.
struct ShortcutField: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    let accessibilityLabel: String
    var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let field = KeyboardShortcuts.RecorderCocoa(for: name, onChange: onChange)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel(accessibilityLabel)
        return field
    }

    func updateNSView(_ field: KeyboardShortcuts.RecorderCocoa, context: Context) {
        field.setAccessibilityLabel(accessibilityLabel)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: KeyboardShortcuts.RecorderCocoa, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? field.intrinsicContentSize.width, height: field.intrinsicContentSize.height)
    }
}
