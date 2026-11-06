import AppKit

/// Turns state changes into moments for the mark.
final class Moments {
    static let shared = Moments()
    private var show: ((Moment) -> Void)?
    private var battery = BatteryInfo()
    private var audio = AudioInfo()

    func start(_ show: @escaping (Moment) -> Void) {
        self.show = show
        let s = SystemState.shared
        battery = s.battery
        audio = s.audio
        s.onSample.append { [weak self] in self?.check() }
        Bluetooth.shared.onConnect = { [weak self] device in
            self?.show?(Moment(glyph: .symbol(device.symbol), title: device.name, subtitle: "Connected"))
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            let name = (try? url?.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName ?? "Drive"
            MainActor.assumeIsolated {
                self?.show?(Moment(glyph: .symbol("externaldrive.fill"), title: name, subtitle: "Connected"))
            }
        }
    }

    private func check() {
        let s = SystemState.shared
        let b = s.battery, a = s.audio
        defer { battery = b; audio = a }
        let level = Int((b.level * 100).rounded())

        if b.present, battery.present {
            if b.pluggedIn, !battery.pluggedIn {
                show?(Moment(glyph: .symbol("bolt.fill"), ringValue: b.level, ringTint: .systemGreen,
                             title: b.charging ? "Charging" : "Plugged in", subtitle: "Plugged in at \(level)%"))
            } else if !b.pluggedIn, battery.pluggedIn {
                show?(Moment(glyph: .symbol("powerplug"), ringValue: b.level, title: "On Battery", subtitle: "Unplugged at \(level)%"))
            } else if !b.pluggedIn, let mark = [20, 10].first(where: { level <= $0 && Int((battery.level * 100).rounded()) > $0 }) {
                show?(Moment(number: "\(mark)", ringValue: b.level, ringTint: .systemRed, title: "Battery low", subtitle: "\(level)% left"))
            }
        }

        if a.muted != audio.muted {
            show?(a.muted
                ? Moment(glyph: .symbol("speaker.slash.fill"), title: "Muted", subtitle: "Sound off")
                : Moment(glyph: .symbol("speaker.wave.2.fill"), ringValue: a.volume, title: "Sound on", subtitle: "Volume \(pct(a.volume))"))
        } else if let output = a.output, let old = audio.output, output.id != old.id {
            show?(Moment(glyph: .symbol(output.symbol), title: output.name, subtitle: "Sound output"))
        }
    }

    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
}
