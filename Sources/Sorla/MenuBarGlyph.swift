import AppKit

// The Sorla mark (dot and three bars, as on the app icon) drawn as a template image for the menu bar.
enum MenuBarGlyph: Equatable {
    case ready
    case loading
    case failed

    // Geometry of site/favicon.svg on its 64-unit grid, cropped to the dot and bars.
    private static let content = CGRect(x: 12.5, y: 17, width: 41.5, height: 30)
    private static let glyphHeight: CGFloat = 14

    func image(accessibilityDescription: String) -> NSImage {
        let scale = Self.glyphHeight / Self.content.height
        let size = NSSize(width: (Self.content.width * scale).rounded(.up), height: 18)
        let isLoading = self == .loading
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: 0, y: (rect.height - Self.glyphHeight) / 2)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -Self.content.minX, y: -Self.content.minY)

            let dot = CGRect(x: 19 - 6.5, y: 32 - 6.5, width: 13, height: 13)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            switch self {
            case .loading:
                ctx.setLineWidth(2.5)
                ctx.strokeEllipse(in: dot.insetBy(dx: 1.25, dy: 1.25))
            case .ready:
                ctx.fillEllipse(in: dot)
            case .failed:
                // An exclamation mark in place of the dot, as tall as the bars, so the failure doesn't rely on colour.
                let stem = CGRect(x: 16.5, y: 17, width: 5, height: 21)
                ctx.addPath(CGPath(roundedRect: stem, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
                ctx.fillPath()
                ctx.fillEllipse(in: CGRect(x: 16.5, y: 42, width: 5, height: 5))
            }

            ctx.setFillColor(NSColor.black.withAlphaComponent(isLoading ? 0.35 : 1).cgColor)
            for (x, y, height) in [(31.0, 25.0, 14.0), (40.0, 17.0, 30.0), (49.0, 23.0, 18.0)] {
                let bar = CGRect(x: x, y: y, width: 5, height: height)
                ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
                ctx.fillPath()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
