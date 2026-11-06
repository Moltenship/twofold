import AppKit
import ServiceManagement
import SwiftUI

final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            for (title, symbol, view) in [
                ("Indicator", "circle.dotted.circle", AnyView(IndicatorSettings())),
                ("Popover", "list.bullet.rectangle", AnyView(PopoverSettings())),
                ("General", "gearshape", AnyView(GeneralSettings())),
            ] {
                let host = NSHostingController(rootView: view.frame(width: 460))
                host.sizingOptions = [.preferredContentSize]
                host.title = title
                let item = NSTabViewItem(viewController: host)
                item.label = title
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                tabs.addTabViewItem(item)
            }
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: Indicator

/// The mark as an AppKit drawing, for previews.
struct MarkPreview: NSViewRepresentable {
    let renderer: MarkRenderer
    var size: CGFloat = 24

    func makeNSView(context: Context) -> PreviewView { PreviewView() }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.renderer = renderer
        view.size = size
        view.needsDisplay = true
    }

    final class PreviewView: NSView {
        var renderer: MarkRenderer?
        var size: CGFloat = 24

        override var intrinsicContentSize: NSSize { NSSize(width: size, height: size) }

        override func draw(_ dirtyRect: NSRect) {
            guard var r = renderer else { return }
            r.foreground = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : NSColor(white: 0, alpha: 0.85)
            // Drawn at size rather than under a scaled transform, so symbols stay vector-sharp.
            let side = min(bounds.width, bounds.height)
            r.scale = side / 24
            r.draw(in: CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side), t: 0)
        }
    }
}

struct IndicatorSettings: View {
    @Bindable private var prefs = Prefs.shared

    private func renderer(level: Double? = nil, style: RingStyle? = nil) -> MarkRenderer {
        let s = SystemState.shared
        func read(_ m: Metric) -> Reading {
            var r = s.reading(m)
            guard let level else { return r }
            r.value = level
            if r.number != nil { r.number = "\(Int(level * 100))" }
            if case let .battery(_, plugged, charging, percent) = r.glyph { r.glyph = .battery(level: level, plugged: plugged, charging: charging, percent: percent) }
            if r.tint != nil { r.tint = level < 0.3 ? .systemRed : .systemGreen }
            return r
        }
        return MarkRenderer(ring: read(prefs.ring), center: read(prefs.center), dots: read(prefs.dots),
                            style: style ?? prefs.style, thickness: prefs.thickness, scale: 1, palette: prefs.palette, foreground: .white)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 40) {
                    ForEach([("Now", nil), ("Low", 0.15), ("High", 0.95)] as [(String, Double?)], id: \.0) { title, level in
                        VStack(spacing: 6) {
                            MarkPreview(renderer: renderer(level: level), size: 56).frame(width: 56, height: 56)
                            Text(title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            Section("Slots") {
                Picker("Ring", selection: $prefs.ring) { metrics }
                Picker("Center", selection: $prefs.center) { metrics }
                Picker("Dots", selection: $prefs.dots) { metrics }
            }
            Section("Ring") {
                HStack(spacing: 12) {
                    ForEach(RingStyle.allCases, id: \.self) { style in
                        VStack(spacing: 4) {
                            MarkPreview(renderer: renderer(style: style), size: 40).frame(width: 40, height: 40)
                            Text(style.title).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(prefs.style == style ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(prefs.style == style ? Color.accentColor : .clear, lineWidth: 1.5))
                        .contentShape(Rectangle())
                        .onTapGesture { prefs.style = style }
                    }
                }
                Picker("Thickness", selection: $prefs.thickness) {
                    ForEach(Thickness.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Icon Size") {
                    Slider(value: $prefs.iconScale, in: 0.85 ... 1.15, step: 0.05)
                }
            }
            Section("Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 9), spacing: 8) {
                    ForEach(Palette.allCases, id: \.self) { palette in
                        Swatch(palette: palette, selected: prefs.palette == palette)
                            .onTapGesture { prefs.palette = palette }
                            .help(palette.title)
                    }
                }
                Text(prefs.palette.title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var metrics: some View {
        ForEach(Metric.allCases) { Text($0.title).tag($0) }
    }
}

struct Swatch: View {
    let palette: Palette
    let selected: Bool

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 22, height: 22)
            .padding(3)
            .overlay(Circle().stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
    }

    private var fill: AnyShapeStyle {
        let stops = (palette.stops ?? []).map { Color(nsColor: $0) }
        return switch palette {
        case .automatic: AnyShapeStyle(AngularGradient(colors: [.green, .yellow, .orange, .red, .blue, .green], center: .center))
        case .monochrome: AnyShapeStyle(Color.primary)
        default: stops.count > 1 ? AnyShapeStyle(LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(stops.first ?? .primary)
        }
    }
}

// MARK: Popover

struct PopoverSettings: View {
    @Bindable private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(prefs.rowOrder) { module in
                        Toggle(isOn: Binding(get: { !prefs.hiddenRows.contains(module) },
                                             set: { on in if on { prefs.hiddenRows.remove(module) } else { prefs.hiddenRows.insert(module) } })) {
                            Label(module.title, systemImage: module.symbol)
                        }
                    }
                    .onMove { prefs.rowOrder.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(height: CGFloat(prefs.rowOrder.count) * 28 + 8)
                .listStyle(.plain)
                .scrollDisabled(true)
            } header: {
                HStack {
                    Text("Rows")
                    Spacer()
                    Button("Reset Order") { prefs.rowOrder = Module.allCases }
                        .controlSize(.small)
                        .disabled(prefs.rowOrder == Module.allCases)
                }
            } footer: {
                Text("Drag to reorder.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show details", isOn: $prefs.showDetails)
            }
            Section {
                ForEach($prefs.profiles) { $profile in
                    HStack {
                        TextField("Name", text: $profile.name).labelsHidden()
                        Text("\(profile.ring.title) · \(profile.center.title) · \(profile.dots.title)")
                            .font(.caption).foregroundStyle(.secondary)
                        Button {
                            prefs.profiles.removeAll { $0.id == profile.id }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button("Save Current Slots") {
                        prefs.profiles.append(Profile(name: "Profile \(prefs.profiles.count + 1)",
                                                      ring: prefs.ring, center: prefs.center, dots: prefs.dots))
                    }
                    if prefs.profiles.isEmpty {
                        Button("Add the three starters") { prefs.profiles = Profile.starters }
                    }
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("A profile saves the three slots. With profiles, a switcher sits at the top of the popover.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: General

struct GeneralSettings: View {
    @Bindable private var prefs = Prefs.shared
    @StateObject private var login = LoginItem()

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $login.enabled)
            }
            Section {
                Picker("Unfold", selection: $prefs.unfoldOn) {
                    ForEach(UnfoldTrigger.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("Click an unfolded icon to open its page. Right-click always opens the popover.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show moments", isOn: $prefs.showMoments)
            } footer: {
                Text("Briefly shows what just happened, like plugging in or a drive connecting.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

final class LoginItem: ObservableObject {
    var enabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            objectWillChange.send()
        }
    }
}
