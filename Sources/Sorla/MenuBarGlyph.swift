import AppKit
import SorlaCore

// The Sorla mark (dot and three bars, as on the app icon) drawn as a template image for the menu bar.
enum MenuBarGlyph {
    // Geometry of site/favicon.svg on its 64-unit grid, cropped to the dot and bars.
    private static let content = CGRect(x: 12.5, y: 17, width: 41.5, height: 30)
    private static let glyphHeight: CGFloat = 14
    private static let badgeSize: CGFloat = 10

    static func image(_ state: MenuBarIconState) -> NSImage {
        image(mark: state.mark, badge: state.badge, accessibilityDescription: state.accessibilityDescription)
    }

    static func image(mark: MenuBarIconState.Mark, badge: MenuBarIconState.Badge? = nil, accessibilityDescription: String) -> NSImage {
        let scale = Self.glyphHeight / Self.content.height
        let width = (Self.content.width * scale).rounded(.up) + (badge == nil ? 0 : Self.badgeSize / 2)
        let size = NSSize(width: width, height: 18)
        let isReady = mark == .ready
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.translateBy(x: 0, y: (rect.height - Self.glyphHeight) / 2)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -Self.content.minX, y: -Self.content.minY)

            let dot = CGRect(x: 19 - 6.5, y: 32 - 6.5, width: 13, height: 13)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            if isReady {
                ctx.fillEllipse(in: dot)
            } else {
                ctx.setLineWidth(2.5)
                ctx.strokeEllipse(in: dot.insetBy(dx: 1.25, dy: 1.25))
            }

            ctx.setFillColor(NSColor.black.withAlphaComponent(isReady ? 1 : 0.35).cgColor)
            for (x, y, height) in [(31.0, 25.0, 14.0), (40.0, 17.0, 30.0), (49.0, 23.0, 18.0)] {
                let bar = CGRect(x: x, y: y, width: 5, height: height)
                ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
                ctx.fillPath()
            }
            ctx.restoreGState()
            if let badge {
                Self.drawBadge(badge, in: rect, ctx: ctx)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    // A small arrow or exclamation mark in the top corner, cut free of the bars so it reads at menu bar size.
    // A shape rather than a colour, so it works in a template image and without colour (#76).
    private static func drawBadge(_ badge: MenuBarIconState.Badge, in rect: NSRect, ctx: CGContext) {
        let frame = NSRect(x: rect.maxX - badgeSize, y: 0, width: badgeSize, height: badgeSize)
        ctx.setBlendMode(.clear)
        ctx.fillEllipse(in: frame.insetBy(dx: -1, dy: -1))
        ctx.setBlendMode(.normal)
        let (name, pointSize): (String, CGFloat) = badge == .restart ? ("arrow.clockwise", 8) : ("exclamationmark", 9)
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .heavy)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return }
        let size = symbol.size
        let symbolFrame = NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
        symbol.draw(in: symbolFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
