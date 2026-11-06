import AppKit
import Observation

enum Metric: String, CaseIterable, Codable, Identifiable {
    case battery, wifi, bluetooth, volume, network, memory, cpu, disk
    var id: String { rawValue }

    var title: String {
        switch self {
        case .battery: "Battery"
        case .wifi: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .volume: "Volume"
        case .network: "Network"
        case .memory: "Memory"
        case .cpu: "CPU"
        case .disk: "Disk"
        }
    }

    var module: Module { Module(rawValue: rawValue)! }
}

/// A popover row and its page. Display has a row but no slot in the mark.
enum Module: String, CaseIterable, Codable, Identifiable {
    case battery, wifi, bluetooth, volume, display, network, memory, cpu, disk
    var id: String { rawValue }

    var title: String {
        switch self {
        case .battery: "Battery"
        case .wifi: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .volume: "Volume"
        case .display: "Display"
        case .network: "Network Activity"
        case .memory: "Memory"
        case .cpu: "CPU Usage"
        case .disk: "Disk"
        }
    }

    var symbol: String {
        switch self {
        case .battery: "battery.100percent"
        case .wifi: "wifi"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .volume: "speaker.wave.2.fill"
        case .display: "display"
        case .network: "arrow.up.arrow.down"
        case .memory: "memorychip"
        case .cpu: "cpu"
        case .disk: "internaldrive"
        }
    }
}

enum RingStyle: String, CaseIterable, Codable {
    case solid, gradient, segmented
    var title: String { rawValue.capitalized }
}

enum Thickness: String, CaseIterable, Codable {
    case thin, regular, bold
    var title: String { rawValue.capitalized }
    var width: CGFloat {
        switch self {
        case .thin: 1.55
        case .regular: 2.17
        case .bold: 2.95
        }
    }
}

enum Palette: String, CaseIterable, Codable {
    case automatic, monochrome, ocean, indigo, violet, rose, sunset, grass, aurora
    var title: String { rawValue.capitalized }

    /// Stops along the ring; one stop means a flat color. Nil means per-metric (automatic) or the menu bar's own color.
    var stops: [NSColor]? {
        switch self {
        case .automatic, .monochrome: nil
        case .ocean: [NSColor(srgbRed: 0.29, green: 0.62, blue: 1.0, alpha: 1)]
        case .indigo: [NSColor(srgbRed: 0.43, green: 0.46, blue: 0.94, alpha: 1)]
        case .violet: [NSColor(srgbRed: 0.66, green: 0.43, blue: 0.96, alpha: 1)]
        case .rose: [NSColor(srgbRed: 0.94, green: 0.43, blue: 0.62, alpha: 1)]
        case .sunset: [NSColor(srgbRed: 0.95, green: 0.53, blue: 0.32, alpha: 1)]
        case .grass: [NSColor(srgbRed: 0.36, green: 0.77, blue: 0.38, alpha: 1)]
        case .aurora: [
            NSColor(srgbRed: 0.22, green: 0.80, blue: 0.68, alpha: 1),
            NSColor(srgbRed: 0.40, green: 0.56, blue: 1.0, alpha: 1),
            NSColor(srgbRed: 0.72, green: 0.42, blue: 0.96, alpha: 1),
            NSColor(srgbRed: 0.95, green: 0.42, blue: 0.64, alpha: 1),
        ]
        }
    }
}

enum UnfoldTrigger: String, CaseIterable, Codable {
    case click, hover, never
    var title: String {
        switch self {
        case .click: "On Click"
        case .hover: "On Hover"
        case .never: "Never"
        }
    }
}

struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var ring: Metric
    var center: Metric
    var dots: Metric

    static let starters = [
        Profile(name: "Work", ring: .cpu, center: .wifi, dots: .memory),
        Profile(name: "Travel", ring: .battery, center: .wifi, dots: .disk),
        Profile(name: "Minimal", ring: .battery, center: .battery, dots: .memory),
    ]
}

@Observable
final class Prefs {
    static let shared = Prefs()
    static let changed = Notification.Name("TwofoldPrefsChanged")

    var ring: Metric { didSet { save() } }
    var center: Metric { didSet { save() } }
    var dots: Metric { didSet { save() } }
    var style: RingStyle { didSet { save() } }
    var thickness: Thickness { didSet { save() } }
    var iconScale: Double { didSet { save() } }
    var palette: Palette { didSet { save() } }
    var rowOrder: [Module] { didSet { save() } }
    var hiddenRows: Set<Module> { didSet { save() } }
    var showDetails: Bool { didSet { save() } }
    var profiles: [Profile] { didSet { save() } }
    var unfoldOn: UnfoldTrigger { didSet { save() } }
    var showMoments: Bool { didSet { save() } }

    private let defaults = UserDefaults.standard
    private var loading = true

    private init() {
        func load<T: Decodable>(_ key: String, _ fallback: T) -> T {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
            return value
        }
        ring = load("ring", .battery)
        center = load("center", .wifi)
        dots = load("dots", .memory)
        style = load("style", .solid)
        thickness = load("thickness", .regular)
        iconScale = load("iconScale", 1.0)
        palette = load("palette", .automatic)
        let order: [Module] = load("rowOrder", Module.allCases)
        // Keep modules added in later versions.
        rowOrder = order + Module.allCases.filter { !order.contains($0) }
        hiddenRows = load("hiddenRows", [])
        showDetails = load("showDetails", true)
        profiles = load("profiles", [])
        unfoldOn = load("unfoldOn", .click)
        showMoments = load("showMoments", true)
        loading = false
    }

    var activeProfile: Profile? {
        profiles.first { $0.ring == ring && $0.center == center && $0.dots == dots }
    }

    func apply(_ profile: Profile) {
        ring = profile.ring
        center = profile.center
        dots = profile.dots
    }

    var visibleRows: [Module] { rowOrder.filter { !hiddenRows.contains($0) } }

    private func save() {
        guard !loading else { return }
        func put<T: Encodable>(_ key: String, _ value: T) {
            defaults.set(try? JSONEncoder().encode(value), forKey: key)
        }
        put("ring", ring)
        put("center", center)
        put("dots", dots)
        put("style", style)
        put("thickness", thickness)
        put("iconScale", iconScale)
        put("palette", palette)
        put("rowOrder", rowOrder)
        put("hiddenRows", hiddenRows)
        put("showDetails", showDetails)
        put("profiles", profiles)
        put("unfoldOn", unfoldOn)
        put("showMoments", showMoments)
        NotificationCenter.default.post(name: Prefs.changed, object: nil)
    }
}
