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
let lead = NSAttributedString(string: "Gratis · Öppen källkod · ", attributes: [.font: NSFont.systemFont(ofSize: 26, weight: .medium), .foregroundColor: muted])
lead.draw(at: NSPoint(x: 460, y: 100))
// The address is set like on the website: system monospace on a chip tinted with the accent.
let address = NSAttributedString(string: "sorla.zerolabs.se", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 24, weight: .medium), .foregroundColor: accent])
let chipOrigin = NSPoint(x: 460 + lead.size().width + 2, y: 100)
let chip = NSRect(x: chipOrigin.x - 10, y: chipOrigin.y - 4, width: address.size().width + 20, height: address.size().height + 10)
accent.withAlphaComponent(0.16).setFill()
NSBezierPath(roundedRect: chip, xRadius: 9, yRadius: 9).fill()
address.draw(at: NSPoint(x: chipOrigin.x, y: chipOrigin.y + 1))

NSGraphicsContext.restoreGraphicsState()
let output = root.appendingPathComponent("site/images/og.jpg")
try rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!.write(to: output)
print("Wrote \(output.path)")
