import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for dimension in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = dimension * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let rect = NSRect(x: 70, y: 70, width: 884, height: 884)
        let tile = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
        NSColor(calibratedRed: 0.09, green: 0.27, blue: 0.24, alpha: 1).setFill()
        tile.fill()
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.23, green: 0.49, blue: 0.42, alpha: 1),
                                  ending: NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.23, alpha: 1))!
        gradient.draw(in: tile, angle: -70)
        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
        tile.lineWidth = 3; tile.stroke()
        NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.84, alpha: 1).setFill()
        let cup = NSBezierPath()
        cup.move(to: NSPoint(x: 284, y: 542)); cup.line(to: NSPoint(x: 708, y: 542))
        cup.line(to: NSPoint(x: 686, y: 362))
        cup.curve(to: NSPoint(x: 496, y: 256), controlPoint1: NSPoint(x: 670, y: 278), controlPoint2: NSPoint(x: 583, y: 256))
        cup.curve(to: NSPoint(x: 306, y: 362), controlPoint1: NSPoint(x: 409, y: 256), controlPoint2: NSPoint(x: 320, y: 278))
        cup.close(); cup.fill()
        let handle = NSBezierPath()
        handle.move(to: NSPoint(x: 700, y: 520))
        handle.curve(to: NSPoint(x: 707, y: 382), controlPoint1: NSPoint(x: 844, y: 562), controlPoint2: NSPoint(x: 828, y: 351))
        NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.84, alpha: 1).setStroke()
        handle.lineWidth = 34; handle.lineCapStyle = .round; handle.stroke()
        let saucer = NSBezierPath(roundedRect: NSRect(x: 268, y: 227, width: 456, height: 22), xRadius: 11, yRadius: 11)
        saucer.fill()
        NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.23, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 300, y: 506, width: 392, height: 67)).fill()
        NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.89, alpha: 0.86).setStroke()
        for x: CGFloat in [409, 496, 583] {
            let steam = NSBezierPath()
            steam.move(to: NSPoint(x: x, y: 617))
            steam.curve(to: NSPoint(x: x + 3, y: 766), controlPoint1: NSPoint(x: x - 50, y: 674), controlPoint2: NSPoint(x: x + 55, y: 709))
            steam.lineWidth = 21; steam.lineCapStyle = .round; steam.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(dimension)x\(dimension)\(suffix).png"))
    }
}
print("Generated Brew icon artwork")
