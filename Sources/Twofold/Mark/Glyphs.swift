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

    static func rounded(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// The menu bar battery: a body filled to the level and a small cap.
    static func battery(_ ctx: CGContext, in rect: CGRect, level: Double, charging: Bool, color: NSColor, alpha: CGFloat) {
        let cap = CGRect(x: rect.maxX - 1.6, y: rect.midY - 2, width: 1.6, height: 4)
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width - 2.2, height: rect.height)
        let path = CGPath(roundedRect: body, cornerWidth: 3.4, cornerHeight: 3.4, transform: nil)
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(color.withAlphaComponent(0.35).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: cap, cornerWidth: 0.8, cornerHeight: 0.8, transform: nil))
        ctx.fillPath()
        let fill: NSColor = charging ? .systemGreen : level <= 0.2 ? .systemRed : color
        ctx.addPath(path)
        ctx.clip()
        ctx.setFillColor(fill.cgColor)
        ctx.fill(CGRect(x: body.minX, y: body.minY, width: body.width * CGFloat(min(max(level, 0), 1)), height: body.height))
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
