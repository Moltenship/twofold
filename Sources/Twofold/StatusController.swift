import AppKit

enum StatusMotion {
    static let unfoldDuration: Double = 0.52
    static let foldDuration: Double = 0.45
    static let idleFold: Double = 6
    static let hoverFold: Double = 0.35
    static let momentIn: Double = 0.35
    static let momentHold: Double = 2.5
    static let momentOut: Double = 0.4
}

/// Draws the mark at the controller's current progress. Clicks fall through to the status button.
final class MarkView: NSView {
    var renderer: MarkRenderer?
    var t: CGFloat = 0
    var crossfade = false
    var moment: Moment?
    var momentProgress: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard var r = renderer, let ctx = NSGraphicsContext.current?.cgContext else { return }
        r.foreground = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : NSColor(white: 0, alpha: 0.85)
        guard crossfade, t > 0, t < 1 else {
            r.draw(in: bounds, t: t, moment: moment, momentProgress: momentProgress)
            return
        }
        for (frame, alpha) in [(CGFloat(0), 1 - t), (1, t)] {
            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            r.draw(in: bounds, t: frame)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }
}

final class StatusController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: 24)
    private let view = MarkView()
    private let popover = NSPopover()
    private let model = PopoverModel()
    private var renderer: MarkRenderer

    /// 0 folded, 1 unfolded.
    private var t: CGFloat = 0
    private var target: CGFloat = 0
    private var animationStart: CFTimeInterval = 0
    private var animationFrom: CGFloat = 0
    private var link: CADisplayLink?

    private var idleTimer: Timer?
    private var hoverFold: Timer?
    private var outsideMonitor: Any?
    private var popoverClosedAt: Date = .distantPast

    private var moments: [Moment] = []
    private var moment: Moment?
    private var momentStart: CFTimeInterval = 0

    override init() {
        renderer = Self.makeRenderer()
        super.init()
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        view.frame = button.bounds
        view.autoresizingMask = [.width, .height]
        button.addSubview(view)
        button.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = PopoverController(model: model) { [weak self] in self?.popover.performClose(nil) }

        SystemState.shared.onSample.append { [weak self] in self?.refresh() }
        NotificationCenter.default.addObserver(forName: Prefs.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    private static func makeRenderer() -> MarkRenderer {
        let p = Prefs.shared, s = SystemState.shared
        return MarkRenderer(ring: s.reading(p.ring), center: s.reading(p.center), dots: s.reading(p.dots),
                            style: p.style, thickness: p.thickness, scale: p.iconScale, palette: p.palette, foreground: .white)
    }

    private var height: CGFloat { item.button?.bounds.height ?? NSStatusBar.system.thickness }

    private func refresh() {
        renderer = Self.makeRenderer()
        view.renderer = renderer
        let p = Prefs.shared
        item.button?.setAccessibilityLabel([p.ring, p.center, p.dots].map { SystemState.shared.reading($0).spoken }.joined(separator: ", "))
        layoutItem()
    }

    private func layoutItem() {
        let width = renderer.width(at: view.crossfade ? (t > 0 ? 1 : 0) : t, height: height)
        if abs(item.length - width) > 0.25 { item.length = ceil(width) }
        view.t = t
        view.needsDisplay = true
    }

    // MARK: Clicks

    @objc private func clicked() {
        guard let event = NSApp.currentEvent, let button = item.button else { return }
        // A click on the item while the popover is open first closes it (transient); don't reopen.
        if Date().timeIntervalSince(popoverClosedAt) < 0.3 { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            show(page: nil, from: button.bounds)
            return
        }
        if t == 1, target == 1 {
            // The action's event sits at the button's center whatever was clicked, so ask where the pointer is.
            guard let window = button.window else { return }
            let x = button.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil).x
            if let slot = renderer.slot(atX: x, width: button.bounds.width, height: height) {
                let metric = [Prefs.shared.ring, Prefs.shared.center, Prefs.shared.dots][slot]
                show(page: metric.module, from: renderer.slotFrame(slot, width: button.bounds.width, height: height))
            } else {
                show(page: nil, from: button.bounds)
            }
            return
        }
        switch Prefs.shared.unfoldOn {
        case .click: target == 1 ? fold() : unfold()
        case .hover, .never: show(page: nil, from: button.bounds)
        }
    }

    // MARK: Hover

    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) {
        hoverFold?.invalidate()
        if Prefs.shared.unfoldOn == .hover, !popover.isShown { unfold() }
    }

    @objc(mouseExited:) func mouseExited(with event: NSEvent) {
        guard Prefs.shared.unfoldOn == .hover, !popover.isShown else { return }
        hoverFold?.invalidate()
        // Exits also fire while the item resizes under the pointer, so fold only once it is really outside.
        hoverFold = Timer.scheduledTimer(withTimeInterval: StatusMotion.hoverFold, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.popover.isShown { self.hoverFold?.invalidate() } else if !self.pointerInside { self.fold() }
            }
        }
    }

    private var pointerInside: Bool {
        // The status item's own window can count as outside.
        item.button?.window?.frame.contains(NSEvent.mouseLocation) == true
    }

    private func show(page: Module?, from rect: NSRect) {
        guard let button = item.button else { return }
        idleTimer?.invalidate()
        model.page = page
        model.opened()
        NSApp.activate()
        popover.show(relativeTo: NSRect(x: rect.minX, y: 0, width: rect.width, height: button.bounds.height), of: button, preferredEdge: .minY)
        // A popover that isn't key drops the first click inside it.
        popover.contentViewController?.view.window?.makeKey()
        button.highlight(true)
    }

    func popoverDidClose(_ notification: Notification) {
        popoverClosedAt = Date()
        item.button?.highlight(false)
        model.closed()
        if target == 1, !(Prefs.shared.unfoldOn == .hover && pointerInside) { fold() }
    }

    // MARK: Unfold

    private func unfold() {
        guard target != 1 else { return }
        endMoment()
        moments.removeAll()
        animate(to: 1)
        guard Prefs.shared.unfoldOn == .click else { return }
        armIdleFold()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.popover.isShown, !self.pointerInside else { return }
                self.fold()
            }
        }
    }

    private func fold() {
        idleTimer?.invalidate()
        hoverFold?.invalidate()
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
        animate(to: 0)
    }

    private func armIdleFold() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: StatusMotion.idleFold, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.popover.isShown, !self.pointerInside else { return }
                self.fold()
            }
        }
    }

    private func animate(to value: CGFloat) {
        target = value
        animationFrom = t
        animationStart = CACurrentMediaTime()
        view.crossfade = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        startLink()
    }

    private func startLink() {
        guard link == nil else { return }
        link = view.displayLink(target: self, selector: #selector(step))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        var running = false

        if t != target {
            let duration = (target == 1 ? StatusMotion.unfoldDuration : StatusMotion.foldDuration) * Double(abs(target - animationFrom))
            let f = duration > 0 ? CGFloat(min((now - animationStart) / duration, 1)) : 1
            t = f >= 1 ? target : animationFrom + (target - animationFrom) * f
            running = t != target
        }

        if moment != nil {
            let e = now - momentStart
            let total = StatusMotion.momentIn + StatusMotion.momentHold + StatusMotion.momentOut
            if e < StatusMotion.momentIn {
                view.momentProgress = Ease.out(CGFloat(e / StatusMotion.momentIn))
            } else if e < StatusMotion.momentIn + StatusMotion.momentHold {
                view.momentProgress = 1
            } else if e < total {
                view.momentProgress = 1 - Ease.inOut(CGFloat((e - StatusMotion.momentIn - StatusMotion.momentHold) / StatusMotion.momentOut))
            } else {
                endMoment()
                if let next = moments.first {
                    moments.removeFirst()
                    begin(next)
                }
            }
            running = running || self.moment != nil
        }

        layoutItem()
        if !running {
            link.invalidate()
            self.link = nil
            view.crossfade = false
            layoutItem()
        }
    }

    // MARK: Moments

    /// Moments never interrupt an unfold or an open popover; while one plays, a few more wait their turn.
    func show(_ moment: Moment) {
        guard Prefs.shared.showMoments, target == 0, t == 0, !popover.isShown else { return }
        if self.moment != nil {
            if moments.count < 3, self.moment != moment, moments.last != moment { moments.append(moment) }
            return
        }
        begin(moment)
    }

    private func begin(_ moment: Moment) {
        self.moment = moment
        momentStart = CACurrentMediaTime()
        view.moment = moment
        startLink()
    }

    private func endMoment() {
        moment = nil
        view.moment = nil
        view.momentProgress = 0
    }
}
