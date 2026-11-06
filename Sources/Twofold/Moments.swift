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
            self?.show?(Moment(glyph: .symbol(device.symbol)))
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.show?(Moment(glyph: .symbol("externaldrive.fill"))) }
        }
    }

    private func check() {
        let s = SystemState.shared
        let b = s.battery, a = s.audio
        defer { battery = b; audio = a }
        let level = Int((b.level * 100).rounded())

        if b.present, battery.present {
            if b.pluggedIn, !battery.pluggedIn {
                show?(Moment(glyph: .symbol("bolt.fill"), ringValue: b.level, ringTint: .systemGreen))
            } else if !b.pluggedIn, battery.pluggedIn {
                show?(Moment(glyph: .symbol("powerplug"), ringValue: b.level))
            } else if !b.pluggedIn, let mark = [20, 10].first(where: { level <= $0 && Int((battery.level * 100).rounded()) > $0 }) {
                show?(Moment(number: "\(mark)", ringValue: b.level, ringTint: .systemRed))
            }
        }

        if a.muted != audio.muted {
            show?(a.muted
                ? Moment(glyph: .symbol("speaker.slash.fill"))
                : Moment(glyph: .symbol(a.symbol), ringValue: a.volume))
        } else if let output = a.output, let old = audio.output, output.id != old.id {
            show?(Moment(glyph: .symbol(output.symbol)))
        }
    }
}
