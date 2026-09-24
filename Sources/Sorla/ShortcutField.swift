import AppKit
import KeyboardShortcuts
import SorlaCore
import SwiftUI

// KeyboardShortcuts' recorder fixes its width at 130 pt; this lets Settings size it so longer translations fit.
struct ShortcutField: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    let row: SettingsRow
    var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let field = KeyboardShortcuts.RecorderCocoa(for: name, onChange: onChange)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        Self.giveAccessibleName(to: field, from: row)
        return field
    }

    func updateNSView(_ field: KeyboardShortcuts.RecorderCocoa, context: Context) {
        Self.giveAccessibleName(to: field, from: row)
    }

    // The recorder shows only keys, so VoiceOver reads the row's title as its name (#12).
    static func giveAccessibleName(to field: NSView, from row: SettingsRow) {
        field.setAccessibilityLabel(row.title)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: KeyboardShortcuts.RecorderCocoa, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? field.intrinsicContentSize.width, height: field.intrinsicContentSize.height)
    }
}
