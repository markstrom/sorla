import Foundation
import SorlaCore

// Separates "still loading" from "failed" so a failed load doesn't leave the loading glyph up forever.
enum ModelLoadingStatus: Equatable {
    case loading
    case ready
    case failed

    struct MenuBarIcon: Equatable {
        let glyph: MenuBarGlyph
        let accessibilityDescription: String
    }

    static func menuBarIcon(for status: ModelLoadingStatus, phase: DictationPhase) -> MenuBarIcon {
        switch status {
        case .loading:
            return MenuBarIcon(glyph: .loading, accessibilityDescription: String(localized: "Sorla (loading model)"))
        case .failed:
            return MenuBarIcon(glyph: .failed, accessibilityDescription: String(localized: "Sorla (model couldn't be loaded)"))
        case .ready:
            break
        }
        switch phase {
        case .recording:
            return MenuBarIcon(glyph: .ready, accessibilityDescription: String(localized: "Sorla (recording)"))
        case .transcribing:
            return MenuBarIcon(glyph: .ready, accessibilityDescription: String(localized: "Sorla (transcribing)"))
        case .idle:
            return MenuBarIcon(glyph: .ready, accessibilityDescription: "Sorla")
        }
    }
}
