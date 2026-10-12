import AppKit

enum StatusIcon {
    // Draw an explicit foreground instead of relying on menu bar template tinting.
    static func image(active: Bool, foreground: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 20), flipped: false) { _ in
            foreground.setFill()
            foreground.setStroke()
            let cup = NSBezierPath()
            cup.move(to: NSPoint(x: 3.5, y: 13))
            cup.line(to: NSPoint(x: 16.5, y: 13))
            cup.line(to: NSPoint(x: 15.8, y: 7))
            cup.curve(to: NSPoint(x: 10, y: 3.5), controlPoint1: NSPoint(x: 15.3, y: 4.3), controlPoint2: NSPoint(x: 13, y: 3.5))
            cup.curve(to: NSPoint(x: 4.2, y: 7), controlPoint1: NSPoint(x: 7, y: 3.5), controlPoint2: NSPoint(x: 4.7, y: 4.3))
            cup.close()
            cup.lineWidth = 1.7
            cup.lineJoinStyle = .round
            if active { cup.fill() } else { cup.stroke() }
            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 16.5, y: 12))
            handle.curve(to: NSPoint(x: 16, y: 7), controlPoint1: NSPoint(x: 22, y: 13), controlPoint2: NSPoint(x: 21, y: 6))
            handle.lineWidth = 1.7; handle.lineCapStyle = .round; handle.stroke()
            let saucer = NSBezierPath()
            saucer.move(to: NSPoint(x: 3, y: 1.5)); saucer.line(to: NSPoint(x: 17, y: 1.5))
            saucer.lineWidth = 1.7; saucer.lineCapStyle = .round; saucer.stroke()
            if active {
                for x: CGFloat in [7, 12] {
                    let steam = NSBezierPath()
                    steam.move(to: NSPoint(x: x, y: 15.5))
                    steam.curve(to: NSPoint(x: x + 0.5, y: 19), controlPoint1: NSPoint(x: x - 2, y: 17), controlPoint2: NSPoint(x: x + 2.5, y: 17.5))
                    steam.lineWidth = 1.3; steam.lineCapStyle = .round; steam.stroke()
                }
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = active ? "Brew active" : "Brew inactive"
        return image
    }
}
