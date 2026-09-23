// Distinguishes "still loading" from "gave up after failing" so the menu-bar icon doesn't stay
// on the hourglass forever when the model fails to load (both used to read as "not ready yet").
enum ModelLoadingStatus: Equatable {
    case loading
    case ready
    case failed

    struct MenuBarIcon: Equatable {
        let symbolName: String
        let accessibilityDescription: String
    }

    static func menuBarIcon(for status: ModelLoadingStatus, isRecording: Bool) -> MenuBarIcon {
        guard status != .loading else {
            return MenuBarIcon(symbolName: "hourglass", accessibilityDescription: "Prata (loading model)")
        }
        return isRecording
            ? MenuBarIcon(symbolName: "mic.fill", accessibilityDescription: "Prata (recording)")
            : MenuBarIcon(symbolName: "mic", accessibilityDescription: "Prata")
    }
}
