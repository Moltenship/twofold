import AppKit

/// A short event the folded mark shows in its center, and on the ring when it has a value.
struct Moment: Equatable {
    var glyph: Reading.Glyph?
    var number: String?
    var ringValue: Double?
    var ringTint: NSColor?
}

/// Draws the mark at any point of the unfold, `t` = 0 folded … 1 unfolded, in one code path,
/// so the resting mark and every animation frame match. Geometry and timing were measured from
/// the alternative frame by frame; see docs/feature-reference/02-unfold.
struct MarkRenderer {
    var ring: Reading
    var center: Reading
    var dots: Reading
    var style: RingStyle
    var thickness: Thickness
    var scale: CGFloat
    var palette: Palette
    var foreground: NSColor

    // MARK: Geometry of the folded mark

    static let ringStart: CGFloat = 215 * .pi / 180
    static let ringSweep: CGFloat = 256 * .pi / 180
    static let dotAngles: [CGFloat] = [233.2, 257.6, 282.4, 306.8].map { $0 * .pi / 180 }
    /// The folded center glyph's box, so the Wi-Fi comes out 9 pt wide like the alternative's.
    static let foldedGlyph: CGFloat = 10.8

    var radius: CGFloat { 8.7 * scale }
    var dotRadius: CGFloat { 8.7 * scale }
    var lineWidth: CGFloat { thickness.width * max(scale, 0.85) }
    var foldWidth: CGFloat { (24 * scale).rounded() }

    // MARK: Unfolded layout, in "unfolded" coordinates where x runs 0…width

    struct Layout {
        var width: CGFloat
        var ring: CGRect
        var center: CGRect
        var dots: CGRect
    }

    static let pad: CGFloat = 5
    static let gap: CGFloat = 13
    /// The point size macOS draws its own Wi-Fi and Sound items at.
    static let glyphPoint: CGFloat = 15
    static let textFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

    func layout(height: CGFloat) -> Layout {
        let sizes = [ring, center, dots].map(contentSize)
        var x = Self.pad
        var frames: [CGRect] = []
        for size in sizes {
            frames.append(CGRect(x: x, y: (height - size.height) / 2, width: size.width, height: size.height))
            x += size.width + Self.gap
        }
        let width = max(x - Self.gap + Self.pad, foldWidth)
        return Layout(width: width.rounded(.up), ring: frames[0], center: frames[1], dots: frames[2])
    }

    func glyphSize(_ glyph: Reading.Glyph) -> CGSize {
        switch glyph {
        case .battery: Glyphs.batterySize
        case .bluetooth: CGSize(width: 9, height: 14)
        case let .symbol(name, variable):
            Glyphs.symbol(name, variable: variable, point: Self.glyphPoint, weight: .regular, color: foreground)?.size ?? CGSize(width: 16, height: 14)
        }
    }

    func contentSize(_ r: Reading) -> CGSize {
        let g = glyphSize(r.glyph)
        guard let text = r.text else { return g }
        let t = (text as NSString).size(withAttributes: [.font: Self.textFont])
        return CGSize(width: g.width + 4 + ceil(t.width), height: max(g.height, t.height))
    }

    func width(at t: CGFloat, height: CGFloat) -> CGFloat {
        let full = layout(height: height).width
        return foldWidth + (full - foldWidth) * Ease.out(Ease.seg(t, 0, 0.5))
    }

    /// Which slot an x position falls into once unfolded.
    func slot(atX x: CGFloat, width: CGFloat, height: CGFloat) -> Int? {
        let l = layout(height: height)
        let ux = x - (width - l.width)
        for (i, frame) in [l.ring, l.center, l.dots].enumerated() where ux >= frame.minX - Self.gap / 2 && ux <= frame.maxX + Self.gap / 2 {
            return i
        }
        return nil
    }

    func slotFrame(_ index: Int, width: CGFloat, height: CGFloat) -> CGRect {
        let l = layout(height: height)
        let frame = [l.ring, l.center, l.dots][index]
        return frame.offsetBy(dx: width - l.width, dy: 0).insetBy(dx: -Self.gap / 2, dy: 0)
    }

    // MARK: Drawing

    /// Draws into the current NSGraphicsContext. `bounds` is the status item's view; its right edge stays put.
    func draw(in bounds: CGRect, t: CGFloat, moment: Moment? = nil, momentProgress m: CGFloat = 0) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let height = bounds.height
        let l = layout(height: height)
        // Unfolded coordinates sit flush right, and so does the folded mark.
        let dx = bounds.width - l.width
        let c = CGPoint(x: l.width - foldWidth / 2, y: height / 2)
        Self.baseScale = hypot(ctx.ctm.a, ctx.ctm.b)

        ctx.saveGState()
        ctx.translateBy(x: bounds.minX + dx, y: bounds.minY)

        drawRing(ctx, center: c, target: lineTarget(l), t: t, moment: moment, m: m)
        drawCenter(ctx, center: c, frame: l.center, t: t, moment: moment, m: m)
        drawDots(ctx, center: c, frame: l.dots, t: t)

        ctx.restoreGState()
    }

    /// The device scale the mark started drawing at; symbols under a scaled transform re-render at their drawn size.
    private static var baseScale: CGFloat = 1

    // MARK: Ring

    private func lineTarget(_ l: Layout) -> (center: CGPoint, length: CGFloat) {
        let f = l.ring
        switch ring.glyph {
        case .battery:
            return (CGPoint(x: f.minX + Glyphs.batteryBody.width / 2, y: f.midY), Glyphs.batteryBody.width)
        default:
            let g = glyphSize(ring.glyph)
            return (CGPoint(x: f.minX + g.width / 2, y: f.midY), min(g.width, 16))
        }
    }

    private func ringColors(value: Double, tint: NSColor?) -> [NSColor] {
        if let stops = palette.stops { return stops }
        if palette == .monochrome { return [foreground] }
        return [tint ?? foreground]
    }

    private func drawRing(_ ctx: CGContext, center c: CGPoint, target: (center: CGPoint, length: CGFloat), t: CGFloat, moment: Moment?, m: CGFloat) {
        let spin = Ease.smooth(Ease.seg(t, 0, 0.36))
        let k = Ease.smooth(Ease.seg(t, 0.18, 0.52))
        let travel = Ease.smooth(Ease.seg(t, 0, 0.5))
        let fade = Ease.smooth(Ease.seg(t, 0.52, 0.7))

        func arc(_ value: Double, tint: NSColor?, alpha: CGFloat) {
            let v = CGFloat(min(max(value, 0), 1))
            let arcLength = radius * Self.ringSweep * v
            let mid0 = Self.ringStart - Self.ringSweep * v / 2
            // Travel direction at the midpoint when running clockwise.
            let theta0 = mid0 - .pi / 2
            var norm = theta0.truncatingRemainder(dividingBy: 2 * .pi)
            if norm > .pi { norm -= 2 * .pi }
            if norm <= -.pi { norm += 2 * .pi }
            // One extra clockwise turn lands the arc level at the top, the way the alternative spins it.
            let delta = -(2 * .pi + norm)
            let mid = mid0 + delta * spin
            let orbit = CGPoint(x: c.x + (target.center.x - c.x) * travel, y: c.y + (target.center.y - radius - c.y) * travel)
            let midPoint = CGPoint(x: orbit.x + radius * cos(mid), y: orbit.y + radius * sin(mid))
            let curve = Arc(mid: midPoint, theta: mid - .pi / 2, kappa: -(1 - k) / radius,
                            length: arcLength + (target.length - arcLength) * k)

            let colors = ringColors(value: value, tint: tint)
            let segmented = style == .segmented ? 1 - k : 0
            let gradient = style == .gradient || colors.count > 1 ? 1 - k : 0
            let fullLength = radius * Self.ringSweep
            curve.stroke(ctx, width: lineWidth, alpha: alpha, segments: segmented, dash: fullLength / 10) { f in
                var color = Glyphs.sample(colors, at: f)
                if gradient > 0, colors.count == 1 { color = color.withAlphaComponent(color.alphaComponent * (1 - gradient * 0.7 * (1 - f))) }
                return Glyphs.mix(color, foreground, k)
            }
        }

        let bolt = ring.glyph.isPlugged && (moment?.ringValue == nil || m == 0) ? 1 - Ease.smooth(Ease.seg(t, 0, 0.2)) : 0
        if bolt > 0 { ctx.beginTransparencyLayer(auxiliaryInfo: nil) }
        if let moment, m > 0, let value = moment.ringValue {
            arc(ring.value, tint: ring.tint, alpha: (1 - m) * (1 - fade))
            arc(value, tint: moment.ringTint, alpha: m * (1 - fade))
        } else {
            arc(ring.value, tint: ring.tint, alpha: 1 - fade)
        }
        if bolt > 0 {
            drawTipBolt(ctx, center: c, value: ring.value, alpha: bolt)
            ctx.endTransparencyLayer()
        }

        if fade > 0 {
            let g = glyphSize(ring.glyph)
            let frame = CGRect(x: target.center.x - (ring.glyph.isBattery ? Glyphs.batteryBody.width / 2 : g.width / 2),
                               y: target.center.y - g.height / 2, width: g.width, height: g.height)
            drawContent(ring, at: frame.origin, height: g.height, alpha: fade, scale: settle(t))
        }
    }

    /// While plugged in, a bolt sits on the ring's tip, cut out of the stroke beneath it.
    private func drawTipBolt(_ ctx: CGContext, center c: CGPoint, value: Double, alpha: CGFloat) {
        let a = Self.ringStart - Self.ringSweep * CGFloat(min(max(value, 0), 1))
        let tip = CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
        let color = Glyphs.sample(ringColors(value: value, tint: ring.tint), at: 1)
        let point = (6 * scale * 4).rounded() / 4
        guard let bolt = Glyphs.symbol("bolt.fill", point: point, weight: .bold, color: color),
              let halo = Glyphs.symbol("bolt.fill", point: point, weight: .black, color: .black) else { return }
        func rect(_ size: CGSize, _ k: CGFloat) -> CGRect {
            CGRect(x: tip.x - size.width * k / 2, y: tip.y - size.height * k / 2, width: size.width * k, height: size.height * k)
        }
        halo.draw(in: rect(halo.size, 1.4), from: .zero, operation: .destinationOut, fraction: alpha)
        bolt.draw(in: rect(bolt.size, 1), from: .zero, operation: .sourceOver, fraction: alpha)
    }

    private func settle(_ t: CGFloat) -> CGFloat { 0.86 + 0.14 * Ease.out(Ease.seg(t, 0.55, 1)) }

    // MARK: Center

    private func drawCenter(_ ctx: CGContext, center c: CGPoint, frame: CGRect, t: CGFloat, moment: Moment?, m: CGFloat) {
        let move = Ease.smooth(Ease.seg(t, 0.02, 0.5))
        let full = contentSize(center)
        let glyph = glyphSize(center.glyph)
        let small = Self.foldedGlyph * scale / max(glyph.width, glyph.height) * (center.glyph == .bluetooth ? 0.9 : 1)
        // The glyph's center travels from the ring's center to its unfolded spot.
        let target = CGPoint(x: frame.minX + glyph.width / 2, y: frame.midY)
        let p = CGPoint(x: c.x + (target.x - c.x) * move, y: c.y + (target.y - c.y) * move)
        let s = small + (1 - small) * move

        if let number = center.number {
            // Numbers crossfade into the unfolded glyph and value as they travel.
            let swap = Ease.smooth(Ease.seg(t, 0.12, 0.45))
            let normal = 1 - (moment != nil ? m : 0)
            drawNumber(number, at: p, scale: 1 + move * 0.6, alpha: (1 - swap) * normal)
            if swap > 0 {
                drawContent(center, at: CGPoint(x: p.x - glyph.width / 2, y: p.y - full.height / 2), height: full.height, alpha: swap, scale: s * (0.9 + 0.1 * swap))
            }
        } else {
            let normal = 1 - (moment != nil ? m : 0)
            ctx.saveGState()
            ctx.translateBy(x: p.x, y: p.y)
            ctx.scaleBy(x: s, y: s)
            // The folded glyph turns into the system's regular one as it grows.
            let origin = CGPoint(x: -glyph.width / 2, y: -full.height / 2)
            drawContent(center, at: origin, height: full.height, alpha: normal * (1 - move), scale: 1, textAlpha: 0, folded: true)
            drawContent(center, at: origin, height: full.height, alpha: normal * move, scale: 1, textAlpha: Ease.smooth(Ease.seg(t, 0.5, 0.75)))
            ctx.restoreGState()
        }

        if let moment, m > 0 {
            if let number = moment.number {
                drawNumber(number, at: c, scale: 1, alpha: m)
            } else if let g = moment.glyph {
                let size = glyphSize(g)
                let sm = Self.foldedGlyph * scale / max(size.width, size.height)
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.scaleBy(x: sm, y: sm)
                drawGlyph(g, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height), alpha: m, folded: true)
                ctx.restoreGState()
            }
        }
    }

    private func drawNumber(_ text: String, at p: CGPoint, scale s: CGFloat, alpha: CGFloat) {
        guard alpha > 0 else { return }
        let size = (text.count >= 3 ? 7.4 : 9.2) * scale
        let font = Glyphs.rounded(size: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground.withAlphaComponent(alpha)]
        let str = text as NSString
        let sz = str.size(withAttributes: attrs)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.scaleBy(x: s, y: s)
        str.draw(at: CGPoint(x: -sz.width / 2, y: -sz.height / 2 + font.descender * 0.15), withAttributes: attrs)
        ctx.restoreGState()
    }

    // MARK: Dots

    private func drawDots(_ ctx: CGContext, center c: CGPoint, frame: CGRect, t: CGFloat) {
        let lit = dots.value > 0 ? max(1, Int((dots.value * 4).rounded())) : 0
        let fade = Ease.smooth(Ease.seg(t, 0.52, 0.7))
        let rowStart = frame.minX + 1.5
        for i in 0 ..< 4 {
            // Staggered starts spread the dots out, then bunch them in their row.
            let move = Ease.inOut(Ease.seg(t, CGFloat(i) * 0.035, 0.42 + CGFloat(i) * 0.035))
            let a = Self.dotAngles[i]
            let start = CGPoint(x: c.x + dotRadius * cos(a), y: c.y + dotRadius * sin(a))
            let end = CGPoint(x: rowStart + CGFloat(i) * 3.1, y: frame.midY)
            // A slight arc on the way, like the alternative's dots dropping into line.
            let lift = sin(move * .pi) * 1.2
            let p = CGPoint(x: start.x + (end.x - start.x) * move, y: start.y + (end.y - start.y) * move - lift)
            let on = i < lit
            let d0: CGFloat = on ? 2.6 * scale : 1.95 * scale
            let d = d0 + (1.9 - d0) * move
            let alpha = (on ? 1 : 0.4) * (1 - fade)
            guard alpha > 0 else { continue }
            ctx.setFillColor(foreground.withAlphaComponent(foreground.alphaComponent * alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
        }
        if fade > 0 {
            let size = contentSize(dots)
            drawContent(dots, at: CGPoint(x: frame.minX, y: frame.midY - size.height / 2), height: size.height, alpha: fade, scale: settle(t))
        }
    }

    // MARK: Glyphs and labels

    /// An unfolded icon with its value, scaled about its center.
    private func drawContent(_ r: Reading, at origin: CGPoint, height: CGFloat, alpha: CGFloat, scale s: CGFloat, textAlpha: CGFloat = 1,
                             folded: Bool = false) {
        guard alpha > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let size = contentSize(r)
        let g = glyphSize(r.glyph)
        ctx.saveGState()
        let mid = CGPoint(x: origin.x + size.width / 2, y: origin.y + height / 2)
        ctx.translateBy(x: mid.x, y: mid.y)
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: -mid.x, y: -mid.y)
        drawGlyph(r.glyph, in: CGRect(x: origin.x, y: origin.y + (height - g.height) / 2, width: g.width, height: g.height), alpha: alpha, folded: folded)
        if let text = r.text, textAlpha > 0 {
            let attrs: [NSAttributedString.Key: Any] = [.font: Self.textFont, .foregroundColor: foreground.withAlphaComponent(alpha * textAlpha)]
            let ts = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: origin.x + g.width + 4, y: origin.y + (height - ts.height) / 2), withAttributes: attrs)
        }
        ctx.restoreGState()
    }

    /// Folded, glyphs are semibold and centered on their ink, as the alternative draws them.
    private func drawGlyph(_ glyph: Reading.Glyph, in rect: CGRect, alpha: CGFloat, folded: Bool = false) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        switch glyph {
        case let .symbol(name, variable):
            // NSImage rasterizes symbols for the size it is asked for, so under a scaled transform ask for the larger size.
            let k = hypot(ctx.ctm.a, ctx.ctm.b) / Self.baseScale
            let weight: NSFont.Weight = folded ? .semibold : .regular
            guard folded || abs(k - 1) > 0.02 else {
                Glyphs.symbol(name, variable: variable, point: Self.glyphPoint, weight: weight, color: foreground)?
                    .draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
                return
            }
            guard let image = Glyphs.symbol(name, variable: variable, point: (Self.glyphPoint * k * 4).rounded() / 4, weight: weight, color: foreground)
            else { return }
            ctx.saveGState()
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.scaleBy(x: 1 / k, y: 1 / k)
            let ink = folded ? Glyphs.inkOffset(image) : .zero
            image.draw(in: CGRect(x: -image.size.width / 2 - ink.x, y: -image.size.height / 2 - ink.y, width: image.size.width, height: image.size.height),
                       from: .zero, operation: .sourceOver, fraction: alpha)
            ctx.restoreGState()
        case let .battery(level, plugged, charging, percent):
            Glyphs.battery(ctx, in: rect, level: level, plugged: plugged, charging: charging, percent: percent, color: foreground, alpha: alpha)
        case .bluetooth:
            Glyphs.bluetooth(ctx, in: rect, color: foreground, alpha: alpha)
        }
    }
}

extension Reading.Glyph {
    var isPlugged: Bool {
        if case let .battery(_, plugged, _, _) = self { plugged } else { false }
    }

    var isBattery: Bool { if case .battery = self { true } else { false } }
}

/// A piece of a circle (or a straight line when kappa is 0) given by its midpoint, direction there, curvature and length.
struct Arc {
    var mid: CGPoint
    var theta: CGFloat
    var kappa: CGFloat
    var length: CGFloat

    func point(_ s: CGFloat) -> CGPoint {
        if abs(kappa) < 1e-4 {
            return CGPoint(x: mid.x + cos(theta) * s, y: mid.y + sin(theta) * s)
        }
        return CGPoint(x: mid.x + (sin(theta + kappa * s) - sin(theta)) / kappa,
                       y: mid.y + (cos(theta) - cos(theta + kappa * s)) / kappa)
    }

    /// `segments` 0…1 blends from a continuous stroke to dashes of `dash` length; `color` takes 0…1 along the arc.
    func stroke(_ ctx: CGContext, width: CGFloat, alpha: CGFloat, segments: CGFloat, dash: CGFloat, color: (CGFloat) -> NSColor) {
        guard length > 0.05, alpha > 0.001 else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setLineWidth(width)
        let first = color(0), last = color(1)
        let uniform = segments == 0 && first.isEqual(last)
        if uniform {
            ctx.setLineCap(.round)
            ctx.setStrokeColor(first.cgColor)
            ctx.addPath(path(steps: 32))
            ctx.strokePath()
        } else {
            // Short butt-capped pieces; dashes skip the gap part of each period, measured from the arc's start.
            let steps = max(24, Int(length / 0.35))
            let gapFraction = 0.36 * segments
            ctx.setLineCap(.butt)
            for i in 0 ..< steps {
                let s0 = CGFloat(i) / CGFloat(steps), s1 = CGFloat(i + 1) / CGFloat(steps)
                let along = (s0 + s1) / 2 * length
                if gapFraction > 0, along.truncatingRemainder(dividingBy: dash) > dash * (1 - gapFraction) { continue }
                let a = point(-length / 2 + s0 * length), b = point(-length / 2 + s1 * length)
                // Overdraw a hair to hide seams between pieces.
                let dir = CGPoint(x: b.x - a.x, y: b.y - a.y)
                ctx.setStrokeColor(color((s0 + s1) / 2).cgColor)
                ctx.move(to: CGPoint(x: a.x - dir.x * 0.15, y: a.y - dir.y * 0.15))
                ctx.addLine(to: b)
                ctx.strokePath()
            }
            if segments < 0.5 {
                for (s, f) in [(-length / 2, CGFloat(0)), (length / 2, CGFloat(1))] {
                    let p = point(s)
                    ctx.setFillColor(color(f).cgColor)
                    ctx.fillEllipse(in: CGRect(x: p.x - width / 2, y: p.y - width / 2, width: width, height: width))
                }
            }
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private func path(steps: Int) -> CGPath {
        let p = CGMutablePath()
        for i in 0 ... steps {
            let pt = point(-length / 2 + length * CGFloat(i) / CGFloat(steps))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

enum Ease {
    static func seg(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(max((t - a) / (b - a), 0), 1) }
    static func smooth(_ x: CGFloat) -> CGFloat { x * x * (3 - 2 * x) }
    static func out(_ x: CGFloat) -> CGFloat { 1 - pow(1 - x, 3) }
    static func inOut(_ x: CGFloat) -> CGFloat { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
}
