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
        var restartBadge = false
    }

    // A replaced Sorla can't paste until it restarts, so the icon says so before anyone presses the key (#43).
    static func menuBarIcon(for status: ModelLoadingStatus, phase: DictationPhase, restartPending: Bool = false) -> MenuBarIcon {
        let icon = menuBarIcon(for: status, phase: phase)
        guard restartPending else { return icon }
        return MenuBarIcon(glyph: icon.glyph, accessibilityDescription: String(localized: "Sorla (needs a restart)"), restartBadge: true)
    }

    private static func menuBarIcon(for status: ModelLoadingStatus, phase: DictationPhase) -> MenuBarIcon {
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
