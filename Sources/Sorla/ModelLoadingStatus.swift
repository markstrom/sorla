// Separates "still loading" from "failed" so a failed load doesn't leave the hourglass up forever.
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
            return MenuBarIcon(symbolName: "hourglass", accessibilityDescription: "Sorla (loading model)")
        }
        return isRecording
            ? MenuBarIcon(symbolName: "mic.fill", accessibilityDescription: "Sorla (recording)")
            : MenuBarIcon(symbolName: "mic", accessibilityDescription: "Sorla")
    }
}
