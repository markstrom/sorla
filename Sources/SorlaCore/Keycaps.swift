import Foundation

// Where running text names a key or shortcut, so the window can set it apart as a keycap (#75).
public enum Keycaps {
    // Longer names first, so "⌃⌥V" isn't taken for a "V" inside it; occurrences never overlap.
    public static func ranges(of keys: [String], in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for key in Set(keys.filter { !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            var searchStart = text.startIndex
            while let range = text.range(of: key, range: searchStart..<text.endIndex) {
                if !found.contains(where: { $0.overlaps(range) }) { found.append(range) }
                searchStart = range.upperBound
            }
        }
        return found.sorted { $0.lowerBound < $1.lowerBound }
    }
}
