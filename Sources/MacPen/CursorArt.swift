import AppKit

/// Draws MacPen's pen cursors. The overlay turns them into `NSCursor`s and the main
/// window shows them as previews, so they are drawn on demand and stay sharp at any size.
struct CursorArt {
    let image: NSImage
    /// In image coordinates with the origin at the top left, as `NSCursor` expects.
    let hotSpot: NSPoint

    var cursor: NSCursor {
        NSCursor(image: image, hotSpot: hotSpot)
    }

    /// The cursor enlarged by `scale`, redrawn rather than resampled.
    func preview(scale: CGFloat) -> NSImage {
        let source = image
        let size = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        return NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
    }

    static func pen(style: AppConfig.CursorStyle, color: NSColor, diameter: CGFloat, alpha: CGFloat) -> CursorArt {
        switch style {
        case .whiteRingDot:
            return whiteRingDot(diameter: diameter)
        case .solidDot:
            return solidDot(color: color, diameter: diameter, alpha: alpha)
        case .crosshair:
            return crosshair(color: color, diameter: diameter, alpha: alpha)
        case .softRing:
            return softRing(color: color, diameter: diameter, alpha: alpha)
        case .pencilOutline:
            return pencilOutline()
        }
    }

    private static func whiteRingDot(diameter: CGFloat) -> CursorArt {
        let imageSize = NSSize(width: 28, height: 28)
        let center = NSPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let ringDiameter = min(14, max(9, diameter * 0.82 + 5.0))
        let image = NSImage(size: imageSize, flipped: false) { _ in
            let ringRect = NSRect(x: center.x - ringDiameter / 2,
                                  y: center.y - ringDiameter / 2,
                                  width: ringDiameter,
                                  height: ringDiameter)
            let coreDiameter = max(2.8, ringDiameter * 0.28)
            let coreRect = NSRect(x: center.x - coreDiameter / 2,
                                  y: center.y - coreDiameter / 2,
                                  width: coreDiameter,
                                  height: coreDiameter)
            let shadowRect = ringRect.insetBy(dx: -0.8, dy: -0.8)

            NSColor.black.withAlphaComponent(0.20).setStroke()
            var outline = NSBezierPath(ovalIn: shadowRect)
            outline.lineWidth = 1.2
            outline.stroke()

            NSColor.white.withAlphaComponent(0.98).setStroke()
            outline = NSBezierPath(ovalIn: ringRect)
            outline.lineWidth = 1.5
            outline.stroke()

            NSColor.white.withAlphaComponent(0.98).setFill()
            NSBezierPath(ovalIn: coreRect).fill()
            return true
        }
        return CursorArt(image: image, hotSpot: center)
    }

    private static func solidDot(color: NSColor, diameter: CGFloat, alpha: CGFloat) -> CursorArt {
        let imageSize = NSSize(width: 28, height: 28)
        let center = NSPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let dotDiameter = min(12, max(6, diameter * 0.9 + 2.0))
        let dotRect = NSRect(x: center.x - dotDiameter / 2,
                             y: center.y - dotDiameter / 2,
                             width: dotDiameter,
                             height: dotDiameter)
        let image = NSImage(size: imageSize, flipped: false) { _ in
            color.withAlphaComponent(alpha * 0.25).setFill()
            NSBezierPath(ovalIn: dotRect.insetBy(dx: -2.8, dy: -2.8)).fill()
            color.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            NSColor.white.withAlphaComponent(0.95).setStroke()
            let outline = NSBezierPath(ovalIn: dotRect.insetBy(dx: 0.6, dy: 0.6))
            outline.lineWidth = 0.9
            outline.stroke()
            return true
        }
        return CursorArt(image: image, hotSpot: center)
    }

    private static func crosshair(color: NSColor, diameter: CGFloat, alpha: CGFloat) -> CursorArt {
        let imageSize = NSSize(width: 30, height: 30)
        let center = NSPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let dotDiameter = min(7, max(3.2, diameter * 0.38))
        let image = NSImage(size: imageSize, flipped: false) { _ in
            let path = NSBezierPath()
            path.lineWidth = 1.0
            path.move(to: NSPoint(x: center.x - 11, y: center.y))
            path.line(to: NSPoint(x: center.x - 4.5, y: center.y))
            path.move(to: NSPoint(x: center.x + 4.5, y: center.y))
            path.line(to: NSPoint(x: center.x + 11, y: center.y))
            path.move(to: NSPoint(x: center.x, y: center.y - 11))
            path.line(to: NSPoint(x: center.x, y: center.y - 4.5))
            path.move(to: NSPoint(x: center.x, y: center.y + 4.5))
            path.line(to: NSPoint(x: center.x, y: center.y + 11))

            color.withAlphaComponent(alpha * 0.9).setStroke()
            path.stroke()
            NSColor.white.withAlphaComponent(0.95).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - dotDiameter / 2,
                                        y: center.y - dotDiameter / 2,
                                        width: dotDiameter,
                                        height: dotDiameter)).fill()
            return true
        }
        return CursorArt(image: image, hotSpot: center)
    }

    private static func softRing(color: NSColor, diameter: CGFloat, alpha: CGFloat) -> CursorArt {
        let imageSize = NSSize(width: 34, height: 34)
        let center = NSPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let ringDiameter = min(16, max(9, diameter * 0.74 + 4.0))
        let ringRect = NSRect(x: center.x - ringDiameter / 2,
                              y: center.y - ringDiameter / 2,
                              width: ringDiameter,
                              height: ringDiameter)
        let image = NSImage(size: imageSize, flipped: false) { _ in
            color.withAlphaComponent(alpha * 0.12).setFill()
            NSBezierPath(ovalIn: ringRect.insetBy(dx: -4.0, dy: -4.0)).fill()
            color.withAlphaComponent(alpha * 0.28).setFill()
            NSBezierPath(ovalIn: ringRect.insetBy(dx: -1.8, dy: -1.8)).fill()
            NSColor.white.withAlphaComponent(0.96).setStroke()
            let outline = NSBezierPath(ovalIn: ringRect)
            outline.lineWidth = 1.3
            outline.stroke()
            return true
        }
        return CursorArt(image: image, hotSpot: center)
    }

    private static func pencilOutline() -> CursorArt {
        let imageSize = NSSize(width: 32, height: 32)
        let hotspot = NSPoint(x: 5.0, y: 6.0)
        let image = NSImage(size: imageSize, flipped: false) { _ in
            func point(_ x: CGFloat, _ yFromTop: CGFloat) -> NSPoint {
                NSPoint(x: x, y: imageSize.height - yFromTop)
            }

            let strokeColor = NSColor.black.withAlphaComponent(0.96)
            NSColor.white.withAlphaComponent(0.98).setFill()
            strokeColor.setStroke()

            let outline = NSBezierPath()
            outline.lineWidth = 1.8
            outline.lineCapStyle = .round
            outline.lineJoinStyle = .round
            outline.move(to: point(hotspot.x, hotspot.y))
            outline.line(to: point(10.6, 11.3))
            outline.line(to: point(22.5, 23.3))
            outline.curve(to: point(24.8, 28.2),
                          controlPoint1: point(24.1, 24.8),
                          controlPoint2: point(25.1, 26.6))
            outline.line(to: point(20.4, 30.9))
            outline.line(to: point(8.5, 18.8))
            outline.line(to: point(hotspot.x, hotspot.y))
            outline.fill()
            outline.stroke()

            let nibLines = NSBezierPath()
            nibLines.lineWidth = 1.45
            nibLines.lineCapStyle = .round
            nibLines.lineJoinStyle = .round
            nibLines.move(to: point(9.8, 12.1))
            nibLines.line(to: point(13.7, 16.0))
            nibLines.move(to: point(8.3, 17.4))
            nibLines.line(to: point(12.8, 12.9))
            nibLines.stroke()

            let ferrule = NSBezierPath()
            ferrule.lineWidth = 1.45
            ferrule.lineCapStyle = .round
            ferrule.move(to: point(20.8, 24.0))
            ferrule.line(to: point(24.0, 27.2))
            ferrule.stroke()

            let accent = NSBezierPath()
            accent.lineWidth = 1.55
            accent.lineCapStyle = .round
            accent.move(to: point(7.7, 2.6))
            accent.line(to: point(11.0, 2.6))
            accent.stroke()
            return true
        }
        return CursorArt(image: image, hotSpot: hotspot)
    }

    static func laser(color: NSColor, diameter: CGFloat) -> CursorArt {
        let imageSize = NSSize(width: 30, height: 30)
        let center = NSPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let outerDiameter = min(12, max(8, diameter * 0.8 + 4))
        let innerDiameter = outerDiameter * 0.40
        let image = NSImage(size: imageSize, flipped: false) { _ in
            let outerRect = NSRect(x: center.x - outerDiameter / 2,
                                   y: center.y - outerDiameter / 2,
                                   width: outerDiameter,
                                   height: outerDiameter)
            let innerRect = NSRect(x: center.x - innerDiameter / 2,
                                   y: center.y - innerDiameter / 2,
                                   width: innerDiameter,
                                   height: innerDiameter)

            color.withAlphaComponent(0.18).setFill()
            NSBezierPath(ovalIn: outerRect.insetBy(dx: -3.2, dy: -3.2)).fill()

            color.withAlphaComponent(0.82).setStroke()
            var path = NSBezierPath(ovalIn: outerRect)
            path.lineWidth = 1.1
            path.stroke()

            NSColor.white.withAlphaComponent(0.95).setStroke()
            path = NSBezierPath(ovalIn: outerRect.insetBy(dx: 1.0, dy: 1.0))
            path.lineWidth = 0.8
            path.stroke()

            color.withAlphaComponent(0.98).setFill()
            NSBezierPath(ovalIn: innerRect).fill()

            NSColor.white.withAlphaComponent(1.0).setFill()
            NSBezierPath(ovalIn: innerRect.insetBy(dx: innerDiameter * 0.22, dy: innerDiameter * 0.22)).fill()
            return true
        }
        return CursorArt(image: image, hotSpot: center)
    }
}
