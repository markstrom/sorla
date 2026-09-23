// Draws the Sorla mark (the website logo) as a macOS app icon and writes Resources/AppIcon.icns.
// Run: swift Scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
// Apple's macOS icon grid: an 824 pt rounded square centred on the 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let unit = body.width / 64

func draw(in ctx: CGContext) {
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(bodyPath)
    ctx.setFillColor(NSColor(srgbRed: 0.043, green: 0.043, blue: 0.047, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let colors = [NSColor.white.withAlphaComponent(0.10).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])
    ctx.restoreGState()

    // Same geometry as site/favicon.svg (64-unit grid, y measured from the top).
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: body.minX + x * unit, y: body.maxY - y * unit) }

    ctx.setFillColor(NSColor(srgbRed: 1, green: 0.231, blue: 0.188, alpha: 1).cgColor)
    let dot = point(19, 32)
    let r = 6.5 * unit
    ctx.fillEllipse(in: CGRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r))

    ctx.setFillColor(NSColor.white.cgColor)
    for (x, y, h) in [(31.0, 25.0, 14.0), (40.0, 17.0, 30.0), (49.0, 23.0, 18.0)] {
        let origin = point(x, y + h)
        let rect = CGRect(x: origin.x, y: origin.y, width: 5 * unit, height: h * unit)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 2.5 * unit, cornerHeight: 2.5 * unit, transform: nil))
        ctx.fillPath()
    }
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let ctx = context.cgContext
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    draw(in: ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try png(size: 1024).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-preview.png"))
print(iconutil.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
