import Foundation

// Finds the string literals Swift source hands to localization, by reading the text rather than running any view.
enum SourceStringKeys {
    struct Key: Equatable {
        // Literal text, with nil where the source interpolates a value.
        let parts: [String?]

        var pattern: String {
            parts.map { $0 ?? #"\(…)"# }.joined()
        }

        // An interpolation makes the key a format string: a specifier for the value, and %% for a plain %.
        func isTranslated(in table: [String: String]) -> Bool {
            guard parts.contains(nil) else { return table[pattern] != nil }
            let specifier = #"%(?:\d+\$)?(?:@|lld|ld|d|llu|lu|u|f|lf)"#
            let regex = parts.map { part in
                part.map { NSRegularExpression.escapedPattern(for: $0.replacingOccurrences(of: "%", with: "%%")) } ?? specifier
            }.joined()
            guard let matcher = try? NSRegularExpression(pattern: "^" + regex + "$") else { return false }
            return table.keys.contains { key in
                matcher.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
            }
        }
    }

    // SwiftUI reads a literal first argument of these as a LocalizedStringKey.
    private static let viewInitializers = #"\b(?:Text|Button|Toggle|Picker|LabeledContent|Section|TextField|Label|Link|Menu|LocalizedStringKey)\(\s*""#
    private static let viewModifiers = #"\.(?:help|accessibilityLabel|accessibilityHint|navigationTitle)\(\s*""#
    private static let localizedString = #"\bString\(localized:\s*""#

    static func localizedKeys(in source: String, includeViews: Bool) throws -> [Key] {
        var patterns = [localizedString]
        if includeViews {
            patterns += [viewInitializers, viewModifiers]
            patterns += try localizedParameterCalls(in: source)
        }
        var starts: [String.Index] = []
        for pattern in patterns {
            let regex = try NSRegularExpression(pattern: pattern)
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range, in: source) else { continue }
                starts.append(source.index(before: range.upperBound))
            }
        }
        return Set(starts).sorted()
            .compactMap { literal(in: source, at: $0)?.key }
            .filter { !$0.pattern.isEmpty }
    }

    // A function of the app's own that takes a LocalizedStringKey, such as the Welcome window's row(title:description:).
    private static func localizedParameterCalls(in source: String) throws -> [String] {
        let declaration = try NSRegularExpression(pattern: #"func (\w+)\(([^)]*)\)"#)
        let parameter = try NSRegularExpression(pattern: #"(\w+)(?:\s+\w+)?:\s*LocalizedStringKey\b"#)
        var patterns: [String] = []
        for match in declaration.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let name = Range(match.range(at: 1), in: source), let list = Range(match.range(at: 2), in: source) else { continue }
            let parameters = String(source[list])
            for label in parameter.matches(in: parameters, range: NSRange(parameters.startIndex..., in: parameters)) {
                guard let range = Range(label.range(at: 1), in: parameters) else { continue }
                patterns.append(#"\b"# + source[name] + #"\([^\n]*?\b"# + parameters[range] + #":\s*""#)
            }
        }
        return patterns
    }

    // Reads the literal whose opening quote is at `start`, following escapes and nested interpolations.
    private static func literal(in source: String, at start: String.Index) -> (key: Key, end: String.Index)? {
        guard source[start] == "\"" else { return nil }
        var parts: [String?] = []
        var text = ""
        var index = source.index(after: start)
        while index < source.endIndex {
            let character = source[index]
            if character == "\"" {
                if !text.isEmpty || parts.isEmpty { parts.append(text) }
                return (Key(parts: parts), index)
            }
            if character == "\n" { return nil }
            guard character == "\\" else {
                text.append(character)
                index = source.index(after: index)
                continue
            }
            let escaped = source.index(after: index)
            guard escaped < source.endIndex else { return nil }
            if source[escaped] == "(" {
                if !text.isEmpty { parts.append(text) }
                text = ""
                parts.append(nil)
                guard let close = closingParenthesis(in: source, after: escaped) else { return nil }
                index = source.index(after: close)
                continue
            }
            switch source[escaped] {
            case "n": text.append("\n")
            case "t": text.append("\t")
            case "0": text.append("\0")
            default: text.append(source[escaped])
            }
            index = source.index(after: escaped)
        }
        return nil
    }

    private static func closingParenthesis(in source: String, after open: String.Index) -> String.Index? {
        var depth = 1
        var index = source.index(after: open)
        while index < source.endIndex {
            switch source[index] {
            case "\"":
                guard let nested = literal(in: source, at: index) else { return nil }
                index = nested.end
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return index }
            default:
                break
            }
            index = source.index(after: index)
        }
        return nil
    }
}
