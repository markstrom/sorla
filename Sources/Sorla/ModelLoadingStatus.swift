import Foundation

// Separates "still loading" from "failed" so a failed load doesn't leave the loading glyph up forever.
enum ModelLoadingStatus: Equatable {
    case loading
    case ready
    case failed

    struct MenuBarIcon: Equatable {
        let glyph: MenuBarGlyph
        let accessibilityDescription: String
    }

    static func menuBarIcon(for status: ModelLoadingStatus, isRecording: Bool) -> MenuBarIcon {
        guard status != .loading else {
            return MenuBarIcon(glyph: .loading, accessibilityDescription: String(localized: "Sorla (loading model)"))
        }
        return isRecording
            ? MenuBarIcon(glyph: .ready, accessibilityDescription: String(localized: "Sorla (recording)"))
            : MenuBarIcon(glyph: .ready, accessibilityDescription: "Sorla")
    }
}
