import AppKit
import SwiftUI

@Observable
final class PopoverModel {
    var page: Module?
    var networks: [WiFiNetwork] = []
    var scanning = false
    var locationAllowed = WiFi.shared.locationAllowed

    func opened() {
        if Prefs.shared.visibleRows.contains(.bluetooth) { SystemState.shared.wantBluetooth() }
        SystemState.shared.sample()
        locationAllowed = WiFi.shared.locationAllowed
        if page == .wifi { scan() }
    }

    func closed() {}

    func open(_ module: Module) {
        withAnimation(.easeInOut(duration: 0.13)) { page = module }
        if module == .wifi { scan() }
    }

    func back() {
        withAnimation(.easeInOut(duration: 0.13)) { page = nil }
    }

    func scan() {
        guard locationAllowed, !scanning else { return }
        scanning = true
        Task {
            let found = await Task.detached { WiFi.scan() }.value
            networks = found
            scanning = false
        }
    }
}

final class PopoverController: NSHostingController<PopoverView> {
    private let model: PopoverModel
    private let close: () -> Void
    private var keys: Any?

    init(model: PopoverModel, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        super.init(rootView: PopoverView(model: model, close: close))
        sizingOptions = [.preferredContentSize]
        WiFi.shared.onAuthorizationChange = { [weak model] in
            model?.locationAllowed = WiFi.shared.locationAllowed
            model?.scan()
            SystemState.shared.sample()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidAppear() {
        super.viewDidAppear()
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            if self.model.page != nil { self.model.back() } else { self.close() }
            return nil
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
    }
}

struct PopoverView: View {
    let model: PopoverModel
    let close: () -> Void

    private var fade: AnyTransition {
        .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.08).delay(0.05)),
                    removal: .opacity.animation(.easeIn(duration: 0.05)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let page = model.page {
                PageView(module: page, model: model)
                    .id(page)
                    .transition(fade)
            } else {
                ListView(model: model, close: close)
                    .transition(fade)
            }
        }
        .frame(width: 362)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: List

struct ListView: View {
    let model: PopoverModel
    let close: () -> Void
    private var prefs: Prefs { .shared }

    var body: some View {
        VStack(spacing: 0) {
            if !prefs.profiles.isEmpty {
                Picker("Profile", selection: Binding(get: { prefs.activeProfile?.id },
                                                     set: { id in prefs.profiles.first { $0.id == id }.map(prefs.apply) })) {
                    ForEach(prefs.profiles) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            ForEach(prefs.visibleRows) { module in
                ModuleRow(module: module, details: prefs.showDetails) { model.open(module) }
            }
            Divider().padding(.vertical, 5).padding(.horizontal, 6)
            MenuRow(title: "Twofold Settings…") {
                close()
                SettingsWindow.shared.show()
            }
            MenuRow(title: "Quit Twofold") { NSApp.terminate(nil) }
        }
        .padding(6)
    }
}

struct ModuleRow: View {
    let module: Module
    let details: Bool
    let open: () -> Void

    var body: some View {
        let s = SystemState.shared
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                well
                VStack(alignment: .leading, spacing: 1) {
                    Text(module == .volume ? "Volume" : module.title).font(.system(size: 13, weight: .medium))
                    if details, module != .volume, let detail = detail(s) {
                        Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(value(s)).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: module == .volume ? 30 : 40)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            if module == .volume {
                VolumeSlider().padding(.leading, 44).padding(.trailing, 8).padding(.bottom, 8)
            }
        }
        .hoverHighlight(radius: 8)
    }

    @ViewBuilder private var well: some View {
        let s = SystemState.shared
        switch module {
        case .wifi:
            Button { WiFi.shared.setPower(!s.wifi.powered); s.sample() } label: {
                Well(symbol: s.wifi.powered ? "wifi" : "wifi.slash", active: s.wifi.powered)
            }
            .buttonStyle(.plain)
        case .volume:
            Button { Audio.shared.setMuted(!s.audio.muted) } label: {
                Well(symbol: s.audio.symbol, active: false)
            }
            .buttonStyle(.plain)
        case .battery:
            Well(symbol: s.battery.charging ? "battery.100percent.bolt" : batterySymbol(s.battery.level), active: false)
        case .bluetooth:
            Well(symbol: "dot.radiowaves.left.and.right", active: s.bluetooth.powered && !s.bluetooth.connected.isEmpty)
        default:
            Well(symbol: module.symbol, active: false)
        }
    }

    private func detail(_ s: SystemState) -> String? {
        switch module {
        case .battery: s.battery.present ? (s.battery.timeText ?? s.battery.stateText) : "No Battery"
        case .wifi: s.wifi.connected ? (s.wifi.ssid ?? "Connected") : s.wifi.stateText
        case .bluetooth: s.bluetooth.powered ? "\(s.bluetooth.devices.count) paired" : "Off"
        case .volume: nil
        case .display: s.displays.first?.name
        case .network: "↓\(NetworkInfo.rate(s.network.down)) · ↑\(NetworkInfo.rate(s.network.up))"
        case .memory: "\(s.memory.used.gb) of \(s.memory.total.gb)"
        case .cpu: "\(percent(s.cpu.user)) user · \(percent(s.cpu.system)) system"
        case .disk: s.disk.root.map { "\($0.free.diskSize) free" }
        }
    }

    private func value(_ s: SystemState) -> String {
        switch module {
        case .battery: s.battery.present ? percent(s.battery.level) : ""
        case .wifi: ""
        case .bluetooth: s.bluetooth.connected.first?.name ?? (s.bluetooth.powered ? "No Devices" : "")
        case .volume: s.audio.muted ? "Muted" : percent(s.audio.volume)
        case .display: s.keepAwake ? "Keep Awake" : ""
        case .network: NetworkInfo.rate(s.network.down + s.network.up)
        case .memory: percent(s.memory.level)
        case .cpu: percent(s.cpu.level)
        case .disk: percent(s.disk.level)
        }
    }
}

struct VolumeSlider: View {
    var body: some View {
        let a = SystemState.shared.audio
        Slider(value: Binding(get: { a.muted ? 0 : a.volume }, set: { Audio.shared.setVolume($0) }), in: 0 ... 1)
            .controlSize(.small)
            .disabled(!a.hasVolume)
    }
}

struct MenuRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Text(title)
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .hoverHighlight(radius: 6)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

struct Well: View {
    let symbol: String
    let active: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(active ? .white : .primary)
            .frame(width: 26, height: 26)
            .background(active ? Color.accentColor : Color.primary.opacity(0.1), in: Circle())
    }
}

func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

func batterySymbol(_ level: Double) -> String {
    switch level {
    case 0.88...: "battery.100percent"
    case 0.63...: "battery.75percent"
    case 0.38...: "battery.50percent"
    case 0.13...: "battery.25percent"
    default: "battery.0percent"
    }
}

/// The rounded gray row highlight under the pointer.
private final class HoverFlag: ObservableObject {
    @Published var on = false
}

private struct HoverHighlight: ViewModifier {
    let radius: CGFloat
    @StateObject private var hover = HoverFlag()

    func body(content: Content) -> some View {
        content
            .background(hover.on ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: radius))
            .onHover { hover.on = $0 }
    }
}

extension View {
    func hoverHighlight(radius: CGFloat) -> some View { modifier(HoverHighlight(radius: radius)) }
}
