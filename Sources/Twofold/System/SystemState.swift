import AppKit
import Observation

/// What a slot draws: a 0…1 value for the ring and dots, a glyph for the unfolded icon and the center.
struct Reading {
    enum Glyph: Equatable {
        case symbol(String, variable: Double? = nil)
        case battery(level: Double, charging: Bool)
        case bluetooth
    }

    var value: Double
    var glyph: Glyph
    /// Shown after the glyph when unfolded, e.g. "65%".
    var text: String?
    /// The center shows this number instead of the glyph.
    var number: String?
    /// Ring color for the Automatic palette; nil means the menu bar's text color.
    var tint: NSColor?
    var spoken: String
}

@Observable
final class SystemState {
    static let shared = SystemState()

    var battery = BatteryInfo()
    var wifi = WiFiInfo()
    var bluetooth = BluetoothInfo()
    var audio = AudioInfo()
    var network = NetworkInfo()
    var memory = MemoryInfo()
    var cpu = CPUInfo()
    var disk = DiskInfo()
    var displays: [DisplayInfo] = []
    var keepAwake = false

    /// Called after every sample, for the mark and moments.
    @ObservationIgnored var onSample: [() -> Void] = []
    @ObservationIgnored private let net = NetworkMonitor()
    @ObservationIgnored private let cpuMonitor = CPUMonitor()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tick = 0

    func start() {
        Audio.shared.onChange = { [weak self] in
            self?.audio = Audio.shared.read()
            self?.notify()
        }
        Audio.shared.start()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { SystemState.shared.sample() }
        }
        timer?.tolerance = 0.3
    }

    func sample() {
        network = net.sample()
        cpu = cpuMonitor.sample()
        memory = MemoryInfo.read()
        battery = BatteryInfo.read()
        wifi = WiFi.shared.read()
        audio = Audio.shared.read()
        // The slower readers run every other tick.
        if tick % 2 == 0 {
            readBluetooth()
            disk = DiskInfo.read()
            displays = Displays.shared.read()
        }
        tick += 1
        notify()
    }

    @ObservationIgnored private var bluetoothWanted = false
    @ObservationIgnored private var readingBluetooth = false

    /// Starts reading Bluetooth; see `Bluetooth.allowed`.
    func wantBluetooth() {
        guard !bluetoothWanted else { return }
        bluetoothWanted = true
        readBluetooth()
    }

    private func readBluetooth() {
        let p = Prefs.shared
        if Bluetooth.allowed || [p.ring, p.center, p.dots].contains(.bluetooth) { bluetoothWanted = true }
        guard bluetoothWanted, !readingBluetooth else { return }
        readingBluetooth = true
        Task {
            let info = await Task.detached { Bluetooth.read() }.value
            bluetooth = info
            readingBluetooth = false
            Bluetooth.shared.listen()
            notify()
        }
    }

    func notify() {
        onSample.forEach { $0() }
    }

    func reading(_ metric: Metric) -> Reading {
        let green = NSColor.systemGreen, orange = NSColor.systemOrange, red = NSColor.systemRed
        func load(_ v: Double) -> NSColor { v < 0.6 ? green : v < 0.85 ? orange : red }
        func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))" }

        switch metric {
        case .battery:
            let b = battery
            let tint: NSColor = b.charging ? green : b.level <= 0.2 ? red : b.lowPowerMode ? .systemYellow : green
            return Reading(value: b.present ? b.level : 0, glyph: .battery(level: b.level, charging: b.charging),
                           text: nil, number: b.present ? percent(b.level) : "–", tint: tint,
                           spoken: b.present ? "Battery \(percent(b.level))%, \(b.stateText)" : "No battery")
        case .wifi:
            let w = wifi
            let tint: NSColor = w.quality >= 0.6 ? green : w.quality >= 0.35 ? orange : red
            return Reading(value: w.quality, glyph: .symbol(w.powered ? "wifi" : "wifi.slash", variable: w.connected ? w.quality : 0),
                           text: nil, number: nil, tint: w.connected ? tint : nil,
                           spoken: w.connected ? "Wi-Fi Connected, \(w.signalText)" : "Wi-Fi \(w.stateText)")
        case .bluetooth:
            let b = bluetooth
            return Reading(value: b.level, glyph: .bluetooth, text: nil, number: nil, tint: .systemBlue,
                           spoken: "Bluetooth \(b.valueText)")
        case .volume:
            let a = audio
            let v = a.muted ? 0 : a.volume
            return Reading(value: v, glyph: .symbol(a.symbol), text: nil, number: nil, tint: .systemBlue,
                           spoken: a.muted ? "Volume muted" : "Volume \(percent(v))%")
        case .network:
            let n = network
            return Reading(value: n.level, glyph: .symbol("arrow.up.arrow.down"), text: NetworkInfo.rate(n.down + n.up),
                           number: nil, tint: .systemBlue,
                           spoken: "Network \(NetworkInfo.rate(n.down)) down, \(NetworkInfo.rate(n.up)) up")
        case .memory:
            let m = memory
            return Reading(value: m.level, glyph: .symbol("memorychip"), text: "\(percent(m.level))%", number: percent(m.level),
                           tint: load(m.level), spoken: "Memory \(percent(m.level))%, \(m.used.gb) of \(m.total.gb)")
        case .cpu:
            let c = cpu
            return Reading(value: c.level, glyph: .symbol("cpu"), text: "\(percent(c.level))%", number: percent(c.level),
                           tint: load(c.level), spoken: "CPU \(percent(c.level))%")
        case .disk:
            let d = disk
            return Reading(value: d.level, glyph: .symbol("internaldrive"), text: "\(percent(d.level))%", number: percent(d.level),
                           tint: load(d.level), spoken: "Disk \(percent(d.level))% used")
        }
    }
}
