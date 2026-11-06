import AppKit

enum Glyphs {
    private struct Key: Hashable {
        var name: String
        var variable: Double?
        var point: CGFloat
        var weight: CGFloat
        var color: String
    }

    private static var cache: [Key: NSImage] = [:]

    static func symbol(_ name: String, variable: Double? = nil, point: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
        let key = Key(name: name, variable: variable.map { ($0 * 20).rounded() / 20 }, point: point, weight: weight.rawValue, color: color.description)
        if let image = cache[key] { return image }
        let config = NSImage.SymbolConfiguration(pointSize: point, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let base = key.variable.map { NSImage(systemSymbolName: name, variableValue: $0, accessibilityDescription: nil) }
            ?? NSImage(systemSymbolName: name, accessibilityDescription: nil)
        let image = base?.withSymbolConfiguration(config)
        if cache.count > 400 { cache.removeAll() }
        cache[key] = image
        return image
    }

    /// How far a symbol's ink box sits from its image's center. Symbol images round their size to whole points,
    /// which leaves the ink up to half a point off-center.
    static func inkOffset(_ image: NSImage) -> CGPoint {
        let b = inkBounds(image)
        return CGPoint(x: b.midX - image.size.width / 2, y: b.midY - image.size.height / 2)
    }

    /// A symbol's ink box in its image's coordinates.
    static func inkBounds(_ image: NSImage) -> CGRect {
        let id = ObjectIdentifier(image)
        if let bounds = inkBounds[id] { return bounds }
        let scale: CGFloat = 4
        let w = Int(image.size.width * scale), h = Int(image.size.height * scale)
        guard w > 0, h > 0, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)
        else { return CGRect(origin: .zero, size: image.size) }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return CGRect(origin: .zero, size: image.size) }
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0 ..< h { for x in 0 ..< w where data[(y * w + x) * 4 + 3] > 80 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        // Rows run top down in the bitmap.
        let bounds = maxX < 0 ? CGRect(origin: .zero, size: image.size)
            : CGRect(x: CGFloat(minX) / scale, y: CGFloat(h - 1 - maxY) / scale, width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        if inkBounds.count > 400 { inkBounds.removeAll() }
        inkBounds[id] = bounds
        return bounds
    }

    private static var inkBounds: [ObjectIdentifier: CGRect] = [:]

    static func rounded(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// The body of the macOS menu bar battery, measured from the system's status item.
    static let batteryBody = CGSize(width: 23, height: 12)
    static let batterySize = CGSize(width: batteryBody.width + 2.4, height: batteryBody.height)

    /// The menu bar battery: a body filled to the level, a cap, and the percentage and plug bolt cut out of it.
    static func battery(_ ctx: CGContext, in rect: CGRect, level: Double, plugged: Bool, charging: Bool, percent: Bool,
                        color: NSColor, alpha: CGFloat) {
        let body = CGRect(x: rect.minX, y: rect.midY - batteryBody.height / 2, width: batteryBody.width, height: batteryBody.height)
        let cap = CGRect(x: body.maxX + 1, y: rect.midY - 2, width: 1.4, height: 4)
        let path = CGPath(roundedRect: body, cornerWidth: 3.8, cornerHeight: 3.8, transform: nil)
        let level = min(max(level, 0), 1)
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(color.withAlphaComponent(color.alphaComponent * 0.4).cgColor)
        ctx.addPath(path)
        ctx.addPath(CGPath(roundedRect: cap, cornerWidth: 0.7, cornerHeight: 1.4, transform: nil))
        ctx.fillPath()
        let fill: NSColor = charging ? .systemGreen : level <= 0.2 ? .systemRed : color
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setFillColor(fill.cgColor)
        ctx.fill(CGRect(x: body.minX, y: body.minY, width: body.width * level, height: body.height))
        ctx.restoreGState()

        // Laid out by ink to match the system item pixel for pixel; its digits sit half a point above center.
        let line = percent ? CTLineCreateWithAttributedString(NSAttributedString(string: "\(Int((level * 100).rounded()))", attributes: [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold), .kern: 0.5, .foregroundColor: NSColor.black,
        ])) : nil
        let textInk = line.map { CTLineGetImageBounds($0, ctx) } ?? .zero
        let bolt = plugged ? symbol("bolt.fill", point: 7, weight: .regular, color: .black) : nil
        let boltInk = bolt.map(inkBounds) ?? .zero
        if line != nil || bolt != nil {
            ctx.setBlendMode(.destinationOut)
            let gap: CGFloat = line != nil && bolt != nil ? 1 : 0
            var x = body.midX - (textInk.width + gap + boltInk.width) / 2
            if let line {
                ctx.textMatrix = .identity
                ctx.textPosition = CGPoint(x: x - textInk.minX, y: body.midY - textInk.midY + 0.5)
                CTLineDraw(line, ctx)
                x += textInk.width + gap
            }
            if let bolt {
                bolt.draw(in: CGRect(x: x - boltInk.minX, y: body.midY - boltInk.midY, width: bolt.size.width, height: bolt.size.height),
                          from: .zero, operation: .destinationOut, fraction: 1)
            }
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// SF Symbols has no Bluetooth rune, so it is drawn.
    static func bluetooth(_ ctx: CGContext, in rect: CGRect, color: NSColor, alpha: CGFloat) {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + w * x, y: rect.minY + h * y) }
        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(color.alphaComponent * alpha).cgColor)
        ctx.setLineWidth(max(1.2, w * 0.16))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: p(0.1, 0.72))
        ctx.addLine(to: p(0.9, 0.28))
        ctx.addLine(to: p(0.5, 0.04))
        ctx.addLine(to: p(0.5, 0.96))
        ctx.addLine(to: p(0.9, 0.72))
        ctx.addLine(to: p(0.1, 0.28))
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Color at 0…1 along evenly spaced stops.
    static func sample(_ stops: [NSColor], at f: CGFloat) -> NSColor {
        guard stops.count > 1 else { return stops.first ?? .labelColor }
        let x = min(max(f, 0), 1) * CGFloat(stops.count - 1)
        let i = min(Int(x), stops.count - 2)
        return mix(stops[i], stops[i + 1], x - CGFloat(i))
    }

    static func mix(_ a: NSColor, _ b: NSColor, _ f: CGFloat) -> NSColor {
        guard f > 0 else { return a }
        guard f < 1 else { return b }
        let x = a.usingColorSpace(.sRGB) ?? a, y = b.usingColorSpace(.sRGB) ?? b
        return NSColor(srgbRed: x.redComponent + (y.redComponent - x.redComponent) * f,
                       green: x.greenComponent + (y.greenComponent - x.greenComponent) * f,
                       blue: x.blueComponent + (y.blueComponent - x.blueComponent) * f,
                       alpha: x.alphaComponent + (y.alphaComponent - x.alphaComponent) * f)
    }
}
