import AppKit
import SorlaCore
import SwiftUI

// One text run in which each key name is a small monospaced chip, so it still wraps with the sentence (#75).
enum KeycapText {
    // A narrow no-break space each side pads the chip; a no-break space inside keeps "Right ⌘" on one line.
    static let padding = "\u{202F}"
    static let joiner = "\u{00A0}"

    static func attributed(_ text: String, keys: [String?], font: Font) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex
        for range in Keycaps.ranges(of: keys.compactMap { $0 }, in: text) {
            result += AttributedString(String(text[cursor..<range.lowerBound]))
            var chip = AttributedString(padding + text[range].replacingOccurrences(of: " ", with: joiner) + padding)
            chip.swiftUI.font = font
            // Adapts to dark mode and Increase Contrast.
            chip.swiftUI.backgroundColor = Color(nsColor: .quaternaryLabelColor)
            result += chip
            cursor = range.upperBound
        }
        result += AttributedString(String(text[cursor...]))
        return result
    }

    // The sentence as written, which is also what VoiceOver reads.
    static func plain(_ attributed: AttributedString) -> String {
        String(attributed.characters)
            .replacingOccurrences(of: padding, with: "")
            .replacingOccurrences(of: joiner, with: " ")
    }
}
