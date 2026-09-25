import Foundation

// Separates "still loading" from "failed" so a failed load doesn't leave the loading glyph up forever;
// the menu bar icon shows a failure with its attention badge (MenuBarIconState, #76).
enum ModelLoadingStatus: Equatable {
    case loading
    case ready
    case failed
}
