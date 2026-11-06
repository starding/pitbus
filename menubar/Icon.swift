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
