import AppKit
import SwiftUI

struct PageView: View {
    let module: Module
    let model: PopoverModel

    var body: some View {
        let s = SystemState.shared
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button(action: model.back) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)).frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                header(s)
            }
            content(s)
            Divider()
            MenuRow(title: link.title, action: link.open)
        }
        .padding(10)
    }

    private var title: String {
        switch module {
        case .volume: "Sound"
        case .network: "Network"
        case .cpu: "CPU"
        default: module.title
        }
    }

    @ViewBuilder private func header(_ s: SystemState) -> some View {
        switch module {
        case .wifi:
            Toggle("", isOn: Binding(get: { s.wifi.powered }, set: { WiFi.shared.setPower($0); s.sample() }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
        case .bluetooth: Value(s.bluetooth.powered ? "On" : "Off")
        case .battery: Value(s.battery.present ? percent(s.battery.level) : "")
        case .volume: Value(s.audio.muted ? "Muted" : percent(s.audio.volume))
        case .network: Value(NetworkInfo.rate(s.network.down + s.network.up))
        case .memory: Value(percent(s.memory.level))
        case .cpu: Value(percent(s.cpu.level))
        case .disk: Value(percent(s.disk.level))
        case .display: EmptyView()
        }
    }

    @ViewBuilder private func content(_ s: SystemState) -> some View {
        switch module {
        case .battery: BatteryPage(b: s.battery)
        case .wifi: WiFiPage(model: model, w: s.wifi)
        case .bluetooth: BluetoothPage(b: s.bluetooth)
        case .volume: SoundPage(a: s.audio)
        case .display: DisplayPage(displays: s.displays)
        case .network: NetworkPage(n: s.network)
        case .memory: MemoryPage(m: s.memory)
        case .cpu: CPUPage(c: s.cpu)
        case .disk: DiskPage(d: s.disk)
        }
    }

    private var link: (title: String, open: () -> Void) {
        func pane(_ id: String) -> () -> Void {
            { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:\(id)")!) }
        }
        let activityMonitor = {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
                                               configuration: .init())
        }
        return switch module {
        case .battery: ("Battery Settings…", pane("com.apple.Battery-Settings.extension"))
        case .wifi: ("Wi-Fi Settings…", pane("com.apple.wifi-settings-extension"))
        case .bluetooth: ("Bluetooth Settings…", pane("com.apple.BluetoothSettings"))
        case .volume: ("Sound Settings…", pane("com.apple.Sound-Settings.extension"))
        case .display: ("Displays Settings…", pane("com.apple.Displays-Settings.extension"))
        case .network: ("Network Settings…", pane("com.apple.Network-Settings.extension"))
        case .memory, .cpu: ("Activity Monitor…", { _ = activityMonitor() })
        case .disk: ("Storage Settings…", pane("com.apple.settings.Storage"))
        }
    }
}

// MARK: Building blocks

struct Value: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
    }
}

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct Line: View {
    let label: String
    let value: String
    var dot: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            Text(label).font(.system(size: 12))
            Spacer()
            Text(value).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
        }
        .frame(height: 24)
    }
}

/// Lines over the last samples, scaled to the largest value.
struct Graph: View {
    let series: [[Double]]
    let colors: [Color]
    var ceiling: Double?

    var body: some View {
        Canvas { ctx, size in
            let top = ceiling ?? max(series.flatMap { $0 }.max() ?? 0, 1)
            for (values, color) in zip(series, colors) where values.count > 1 {
                let step = size.width / CGFloat(max(values.count - 1, 1))
                var line = Path()
                for (i, v) in values.enumerated() {
                    let p = CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(min(v / top, 1)) * (size.height - 2) - 1)
                    i == 0 ? line.move(to: p) : line.addLine(to: p)
                }
                var fill = line
                fill.addLine(to: CGPoint(x: CGFloat(values.count - 1) * step, y: size.height))
                fill.addLine(to: CGPoint(x: 0, y: size.height))
                fill.closeSubpath()
                ctx.fill(fill, with: .color(color.opacity(0.15)))
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
        .frame(height: 64)
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct Bar: View {
    let parts: [(Double, Color)]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(parts.indices, id: \.self) { i in
                    parts[i].1.frame(width: geo.size.width * CGFloat(min(max(parts[i].0, 0), 1)))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
        .background(Color.primary.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct DeviceRow: View {
    let symbol: String
    let title: String
    let detail: String?
    let active: Bool
    var trailing: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Well(symbol: symbol, active: active)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12)).lineLimit(1)
                if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            Spacer()
            if let trailing { Image(systemName: trailing).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
        .hoverHighlight(radius: 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

// MARK: Pages

struct BatteryPage: View {
    let b: BatteryInfo

    var body: some View {
        if !b.present {
            Text("No battery").foregroundStyle(.secondary)
        } else {
            Card {
                Line(label: "Power Source", value: b.pluggedIn ? "Power Adapter" : "Battery")
                Line(label: "State", value: b.stateText)
                if let time = b.timeText { Line(label: "Time", value: time) }
            }
            Card(title: "Energy Mode") {
                Line(label: "Low Power Mode", value: b.lowPowerMode ? "On" : "Off")
            }
            if b.maxCapacity != nil || b.cycleCount != nil {
                Card(title: "Battery Health") {
                    if let max = b.maxCapacity { Line(label: "Maximum Capacity", value: "\(max)%") }
                    if let cycles = b.cycleCount { Line(label: "Cycle Count", value: "\(cycles)") }
                }
            }
        }
    }
}

struct WiFiPage: View {
    let model: PopoverModel
    let w: WiFiInfo

    var body: some View {
        if !w.powered {
            Text("Wi-Fi is off.").font(.system(size: 12)).foregroundStyle(.secondary)
        } else if !model.locationAllowed {
            VStack(alignment: .leading, spacing: 8) {
                Text("macOS treats Wi-Fi network names as location data, so Twofold needs Location access to show your network's name and the networks around you.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Allow Location Access…") { WiFi.shared.requestLocation() }
            }
        } else {
            if let ssid = w.ssid {
                DeviceRow(symbol: "wifi", title: ssid, detail: w.signalText, active: true, trailing: "checkmark") {}
            }
            Card(title: model.scanning && model.networks.isEmpty ? "Searching…" : "Other Networks") {
                ForEach(model.networks.filter { $0.ssid != w.ssid }.prefix(12)) { net in
                    DeviceRow(symbol: "wifi", title: net.ssid, detail: nil, active: false, trailing: net.secure ? "lock.fill" : nil) {
                        join(net)
                    }
                }
            }
        }
    }

    private func join(_ net: WiFiNetwork) {
        var password: String?
        if net.secure {
            let alert = NSAlert()
            alert.messageText = "Join “\(net.ssid)”"
            alert.informativeText = "Leave empty to use the password macOS remembers."
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            alert.accessoryView = field
            alert.addButton(withTitle: "Join")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            password = field.stringValue.isEmpty ? nil : field.stringValue
        }
        let ssid = net.ssid
        Task.detached {
            _ = WiFi.join(ssid, password: password)
            await MainActor.run { SystemState.shared.sample() }
        }
    }
}

struct BluetoothPage: View {
    let b: BluetoothInfo

    var body: some View {
        if !b.powered {
            Text("Bluetooth is off.").font(.system(size: 12)).foregroundStyle(.secondary)
        } else if b.devices.isEmpty {
            Text("No paired devices.").font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(b.devices) { d in
                    let state = d.connected ? (d.battery.map { "Connected · \($0)%" } ?? "Connected") : "Not Connected"
                    DeviceRow(symbol: d.symbol, title: d.name, detail: state, active: d.connected) {
                        Bluetooth.shared.toggle(d.id)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { SystemState.shared.sample() }
                    }
                }
            }
        }
    }
}

struct SoundPage: View {
    let a: AudioInfo

    var body: some View {
        Card(title: "Output Volume") {
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                    .onTapGesture { Audio.shared.setMuted(!a.muted) }
                VolumeSlider()
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(height: 30)
        }
        Card(title: "Output") {
            ForEach(a.outputs) { device in
                DeviceRow(symbol: device.symbol, title: device.name, detail: nil, active: device.id == a.output?.id) {
                    Audio.shared.setOutput(device.id)
                }
            }
        }
    }
}

struct DisplayPage: View {
    let displays: [DisplayInfo]

    var body: some View {
        let s = SystemState.shared
        Card {
            Toggle("Keep Awake", isOn: Binding(get: { s.keepAwake }, set: { on in
                Displays.shared.setKeepAwake(on)
                s.keepAwake = Displays.shared.keepAwake
            }))
            .toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
            .frame(height: 28)
        }
        Card(title: "Displays") {
            ForEach(displays) { d in
                Line(label: d.name, value: [d.resolution, d.refresh].compactMap { $0 }.joined(separator: " · "))
            }
        }
    }
}

struct NetworkPage: View {
    let n: NetworkInfo

    var body: some View {
        Graph(series: [n.history.map(\.down), n.history.map(\.up)], colors: [.blue, .orange])
        Card {
            Line(label: "Download", value: NetworkInfo.rate(n.down), dot: .blue)
            Line(label: "Upload", value: NetworkInfo.rate(n.up), dot: .orange)
        }
        Card {
            Line(label: "Connection", value: n.kind)
            Line(label: "IP Address", value: n.address ?? "–")
        }
    }
}

struct MemoryPage: View {
    let m: MemoryInfo

    var body: some View {
        let total = Double(max(m.total, 1))
        VStack(alignment: .leading, spacing: 6) {
            Bar(parts: [(Double(m.app) / total, .blue), (Double(m.wired) / total, .orange), (Double(m.compressed) / total, .purple)])
            Text("Memory Used \(m.used.gb) of \(m.total.gb)").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Card {
            Line(label: "App Memory", value: m.app.gb, dot: .blue)
            Line(label: "Wired Memory", value: m.wired.gb, dot: .orange)
            Line(label: "Compressed", value: m.compressed.gb, dot: .purple)
            Line(label: "Cached Files", value: m.cached.gb, dot: .gray)
        }
    }
}

struct CPUPage: View {
    let c: CPUInfo

    var body: some View {
        Graph(series: [c.history], colors: [.blue], ceiling: 1)
        Card {
            Line(label: "User", value: percent(c.user), dot: .blue)
            Line(label: "System", value: percent(c.system), dot: .red)
            Line(label: "Idle", value: percent(c.idle), dot: .gray)
        }
        Card {
            Line(label: "Load Average", value: c.load.map { String(format: "%.2f", $0) }.joined(separator: "  "))
            Line(label: "Cores", value: "\(c.cores)")
            Line(label: "Thermal State", value: c.thermalText)
            Line(label: "Uptime", value: c.uptimeText)
        }
    }
}

struct DiskPage: View {
    let d: DiskInfo

    var body: some View {
        ForEach(d.volumes) { v in
            Card {
                HStack(spacing: 8) {
                    Image(systemName: v.isRoot ? "internaldrive" : "externaldrive").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(v.name).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(v.free.diskSize) free of \(v.total.diskSize)").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Bar(parts: [(v.used, v.used > 0.9 ? .red : .blue)])
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}
