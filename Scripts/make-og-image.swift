// Draws the link-preview image for the website (site/images/og.jpg, 1200×630) from the app icon and tagline.
// Run: swift Scripts/make-og-image.swift
import AppKit

let size = NSSize(width: 1200, height: 630)
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let icon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon.icns"))!

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let background = NSGradient(colors: [NSColor(srgbRed: 0.23, green: 0.13, blue: 0.10, alpha: 1), NSColor(srgbRed: 0.043, green: 0.043, blue: 0.047, alpha: 1)])!
background.draw(in: NSRect(origin: .zero, size: size), angle: -35)

icon.draw(in: NSRect(x: 80, y: 155, width: 320, height: 320))

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at point: NSPoint, kern: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .kern: kern,
    ]
    NSAttributedString(string: string, attributes: attributes).draw(at: point)
}

let ink = NSColor(srgbRed: 0.93, green: 0.92, blue: 0.91, alpha: 1)
let muted = NSColor(srgbRed: 0.68, green: 0.67, blue: 0.64, alpha: 1)
let accent = NSColor(srgbRed: 1, green: 0.48, blue: 0.35, alpha: 1)

text("Sorla", size: 44, weight: .semibold, color: muted, at: NSPoint(x: 460, y: 410))
text("Prata. Släpp.", size: 84, weight: .bold, color: ink, at: NSPoint(x: 456, y: 300), kern: -2.5)
text("Klart.", size: 84, weight: .bold, color: accent, at: NSPoint(x: 456, y: 205), kern: -2.5)
text("Svensk diktering för Mac. Allt stannar på datorn", size: 30, weight: .regular, color: muted, at: NSPoint(x: 460, y: 150))
text("Gratis · Öppen källkod · sorla.zerolabs.se", size: 26, weight: .medium, color: muted, at: NSPoint(x: 460, y: 100))

NSGraphicsContext.restoreGraphicsState()
let output = root.appendingPathComponent("site/images/og.jpg")
try rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!.write(to: output)
print("Wrote \(output.path)")
