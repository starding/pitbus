import AppKit

// The icon: one point standing on a timeline among its ticks — a point in time.
// The point is hollow while nothing waits for the person, and solid when a draft waits for confirmation.
// Drawn in code as a template image, so it follows the menu bar's light and dark appearance.
func pitIcon(filled: Bool = false) -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        NSColor.black.set()
        func line(_ a: NSPoint, _ b: NSPoint, _ w: CGFloat) {
            let p = NSBezierPath()
            p.move(to: a)
            p.line(to: b)
            p.lineWidth = w
            p.lineCapStyle = .round
            p.stroke()
        }
        line(NSPoint(x: 1.5, y: 3.5), NSPoint(x: 16.5, y: 3.5), 1.5)
        for x in [3.5, 7.0, 14.5] as [CGFloat] { line(NSPoint(x: x, y: 3.5), NSPoint(x: x, y: 5.5), 1.2) }
        let head = NSRect(x: 11 - 3.3, y: 12.5 - 3.3, width: 6.6, height: 6.6)
        if filled {
            line(NSPoint(x: 11, y: 3.5), NSPoint(x: 11, y: 10), 1.5)
            NSBezierPath(ovalIn: head).fill()
        } else {
            line(NSPoint(x: 11, y: 3.5), NSPoint(x: 11, y: 9.2), 1.5)
            let ring = NSBezierPath(ovalIn: head.insetBy(dx: 0.75, dy: 0.75))
            ring.lineWidth = 1.5
            ring.stroke()
        }
        return true
    }
    img.isTemplate = true
    return img
}

func writePNG(_ rep: NSBitmapImageRep, _ path: String) {
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

// `PitBus --render-icon <png>`: the icon at 8x, idle on a light strip and with a draft waiting on a dark one.
func renderIconPreview(to path: String) {
    let scale: CGFloat = 8, w: CGFloat = 18 * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * 2), pixelsHigh: Int(w), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    for (i, (bg, fg)) in [(NSColor(white: 0.93, alpha: 1), NSColor.black), (NSColor(white: 0.16, alpha: 1), NSColor.white)].enumerated() {
        let rect = NSRect(x: CGFloat(i) * w, y: 0, width: w, height: w)
        bg.setFill()
        rect.fill()
        let tinted = NSImage(size: rect.size, flipped: false) { r in
            pitIcon(filled: i == 1).draw(in: r)
            fg.set()
            r.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: rect)
    }
    NSGraphicsContext.restoreGraphicsState()
    writePNG(rep, path)
}

// The app icon, for Launchpad and Finder: the menu bar glyph in white on a deep slate tile, with the point in the
// orange that marks 「等你」 on the panel. The tile follows macOS's grid: 824 of 1024, centered, corners 185.
func appIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let k = CGFloat(pixels) / 1024
    let tile = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * k, yRadius: 185 * k)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * k)
    shadow.shadowBlurRadius = 20 * k
    shadow.set()
    NSColor(red: 0.13, green: 0.15, blue: 0.20, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(red: 0.22, green: 0.25, blue: 0.32, alpha: 1),
               ending: NSColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1))!.draw(in: shape, angle: -90)
    // the glyph's 18-unit drawing, scaled into the tile with some air around it
    let u = 824 * k / 24, ox = tile.minX + 3 * u, oy = tile.minY + 3.2 * u
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * u, y: oy + y * u) }
    func line(_ a: NSPoint, _ b: NSPoint, _ w: CGFloat) {
        let p = NSBezierPath()
        p.move(to: a)
        p.line(to: b)
        p.lineWidth = w * u
        p.lineCapStyle = .round
        p.stroke()
    }
    NSColor.white.set()
    line(pt(1.5, 3.5), pt(16.5, 3.5), 1.5)
    for x in [3.5, 7.0, 14.5] as [CGFloat] { line(pt(x, 3.5), pt(x, 5.5), 1.2) }
    line(pt(11, 3.5), pt(11, 10), 1.5)
    NSColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: ox + (11 - 3.3) * u, y: oy + (12.5 - 3.3) * u, width: 6.6 * u, height: 6.6 * u)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// `PitBus --render-app-icon <folder.iconset>`: every size macOS wants. After changing the drawing:
//   PitBus --render-app-icon /tmp/PitBus.iconset && iconutil -c icns /tmp/PitBus.iconset -o menubar/PitBus.icns
func renderAppIconSet(to dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for s in [16, 32, 128, 256, 512] {
        writePNG(appIcon(pixels: s), "\(dir)/icon_\(s)x\(s).png")
        writePNG(appIcon(pixels: s * 2), "\(dir)/icon_\(s)x\(s)@2x.png")
    }
}
