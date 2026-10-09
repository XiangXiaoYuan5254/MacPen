import AppKit

// Draws the DMG window's background: light gray with a dashed arrow in the middle, pointing from
// MacPen on the left to the Applications shortcut on the right. The window is 540x380 and the
// icons sit at y = 220 (see Scripts/dmg/settings.py), so the arrow goes between them.
// Writes a 1x and a 2x (Retina) image; dmgbuild combines background@2x.png into the same background.
//
//   swift Scripts/dmg/background.swift <output directory>

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 540.0
let height = 380.0

func render(scale: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width) * scale,
        pixelsHigh: Int(height) * scale,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSColor(calibratedWhite: 0.925, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    // The arrow is centered at (270, 220) from the top left; this context's origin is the bottom left.
    let cx = 270.0
    let cy = height - 220
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: cx - 27, y: cy + 11))
    arrow.line(to: NSPoint(x: cx - 5, y: cy + 11))
    arrow.line(to: NSPoint(x: cx - 5, y: cy + 29))
    arrow.line(to: NSPoint(x: cx + 24, y: cy))
    arrow.line(to: NSPoint(x: cx - 5, y: cy - 29))
    arrow.line(to: NSPoint(x: cx - 5, y: cy - 11))
    arrow.line(to: NSPoint(x: cx - 27, y: cy - 11))
    arrow.close()
    arrow.lineWidth = 1.5
    arrow.lineJoinStyle = .miter
    arrow.setLineDash([4, 3], count: 2, phase: 0)
    NSColor(calibratedWhite: 0.42, alpha: 1).setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try render(scale: 1).write(to: outputDirectory.appendingPathComponent("background.png"))
try render(scale: 2).write(to: outputDirectory.appendingPathComponent("background@2x.png"))
