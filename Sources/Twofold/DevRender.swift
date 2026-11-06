import AppKit

/// `--render-unfold <dir>` and `--render-icon <file>`: offscreen renders for comparing motion
/// with the reference strips and for making the app icon.
enum DevRender {
    static func sampleRenderer(foreground: NSColor = .white, style: RingStyle = .solid, palette: Palette = .automatic) -> MarkRenderer {
        MarkRenderer(
            ring: Reading(value: 0.8, glyph: .battery(level: 0.8, plugged: false, charging: false, percent: false), text: nil, number: "80", tint: .systemGreen, spoken: ""),
            center: Reading(value: 1, glyph: .symbol("wifi", variable: 1), text: nil, number: nil, tint: nil, spoken: ""),
            dots: Reading(value: 0.65, glyph: .symbol("memorychip"), text: "65%", number: "65", tint: nil, spoken: ""),
            style: style, thickness: .regular, scale: 1, palette: palette, foreground: foreground)
    }

    static func png(width: Int, height: Int, scale: CGFloat, background: NSColor?, draw: (CGRect) -> Void) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(CGFloat(width) * scale), pixelsHigh: Int(CGFloat(height) * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if let background {
            background.setFill()
            bounds.fill()
        }
        draw(bounds)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// One PNG per 60 fps frame of the unfold, then of the fold.
    static func unfold(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let r = sampleRenderer()
        let height: CGFloat = 24
        let full = r.layout(height: height).width
        let frames = Int(StatusMotion.unfoldDuration * 60)
        for i in 0 ... frames {
            let t = CGFloat(i) / CGFloat(frames)
            let data = png(width: Int(full) + 20, height: Int(height), scale: 4, background: NSColor(white: 0.17, alpha: 1)) { b in
                let w = r.width(at: t, height: height)
                NSColor(white: 0.24, alpha: 1).setFill()
                NSBezierPath(roundedRect: CGRect(x: b.width - 10 - w, y: 0, width: w, height: height), xRadius: 6, yRadius: 6).fill()
                r.draw(in: CGRect(x: b.width - 10 - w, y: 0, width: w, height: height), t: t)
            }
            try? data?.write(to: dir.appendingPathComponent(String(format: "unfold-%03d.png", i)))
        }
        let styles: [(RingStyle, Palette)] = [(.solid, .automatic), (.gradient, .rose), (.segmented, .violet), (.gradient, .aurora), (.solid, .monochrome)]
        for (n, (style, palette)) in styles.enumerated() {
            let r = sampleRenderer(style: style, palette: palette)
            let data = png(width: 24, height: 24, scale: 8, background: NSColor(white: 0.17, alpha: 1)) { b in r.draw(in: b, t: 0) }
            try? data?.write(to: dir.appendingPathComponent("style-\(n)-\(style.rawValue)-\(palette.rawValue).png"))
        }
        print("wrote \(frames + 1) frames to \(dir.path)")
    }

    static func icon(to file: URL) {
        let r = MarkRenderer(
            ring: Reading(value: 0.78, glyph: .symbol("wifi"), text: nil, number: nil, tint: nil, spoken: ""),
            center: Reading(value: 1, glyph: .symbol("wifi", variable: 1), text: nil, number: nil, tint: nil, spoken: ""),
            dots: Reading(value: 0.75, glyph: .symbol("memorychip"), text: nil, number: nil, tint: nil, spoken: ""),
            style: .gradient, thickness: .regular, scale: 24, palette: .aurora, foreground: .white)
        let data = png(width: 1024, height: 1024, scale: 1, background: nil) { b in
            let tile = b.insetBy(dx: 100, dy: 100)
            let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
            NSGradient(colors: [NSColor(srgbRed: 0.13, green: 0.12, blue: 0.2, alpha: 1), NSColor(srgbRed: 0.04, green: 0.04, blue: 0.07, alpha: 1)])?
                .draw(in: path, angle: -90)
            r.draw(in: CGRect(x: b.midX - 24 * 24 / 2, y: b.midY - 24 * 24 / 2 + 16, width: 24 * 24, height: 24 * 24), t: 0)
        }
        try? data?.write(to: file)
    }
}
