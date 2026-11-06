import AppKit
import CoreLocation
import CoreWLAN

struct WiFiNetwork: Identifiable, Hashable {
    var id: String { ssid }
    var ssid: String
    var rssi: Int
    var secure: Bool
}

struct WiFiInfo: Equatable {
    var available = false
    var powered = false
    var connected = false
    var ssid: String?
    var rssi = 0

    /// 0…1 from RSSI: -90 dBm and below is nothing, -50 dBm and above is full.
    var quality: Double { connected ? min(max(Double(rssi + 90) / 40, 0), 1) : 0 }

    var signalText: String {
        if rssi >= -55 { return "Excellent signal" }
        if rssi >= -67 { return "Good signal" }
        if rssi >= -75 { return "Fair signal" }
        return "Weak signal"
    }

    var stateText: String {
        if !available { return "Not Available" }
        if !powered { return "Off" }
        if connected { return ssid ?? "Connected" }
        return "Not Connected"
    }
}

final class WiFi: NSObject, CLLocationManagerDelegate {
    static let shared = WiFi()
    private let client = CWWiFiClient.shared()
    private let location = CLLocationManager()
    var onAuthorizationChange: (() -> Void)?

    override init() {
        super.init()
        location.delegate = self
    }

    var interface: CWInterface? { client.interface() }

    func read() -> WiFiInfo {
        guard let iface = interface else { return WiFiInfo() }
        var info = WiFiInfo(available: true, powered: iface.powerOn())
        info.rssi = iface.rssiValue()
        info.connected = info.powered && info.rssi != 0
        info.ssid = iface.ssid()
        return info
    }

    func setPower(_ on: Bool) {
        try? interface?.setPower(on)
    }

    // macOS hides network names from apps without Location access.
    var locationAllowed: Bool {
        let status = location.authorizationStatus
        return status == .authorizedAlways || status == .authorized
    }

    var locationDenied: Bool {
        let status = location.authorizationStatus
        return status == .denied || status == .restricted
    }

    func requestLocation() {
        if locationDenied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
        } else {
            location.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.onAuthorizationChange?() }
    }

    /// Blocks for a second or two; call off the main thread.
    nonisolated static func scan() -> [WiFiNetwork] {
        guard let iface = CWWiFiClient.shared().interface(),
              let found = try? iface.scanForNetworks(withName: nil) else { return [] }
        var best: [String: WiFiNetwork] = [:]
        for net in found {
            guard let ssid = net.ssid, !ssid.isEmpty else { continue }
            let item = WiFiNetwork(ssid: ssid, rssi: net.rssiValue, secure: !net.supportsSecurity(.none))
            if (best[ssid]?.rssi ?? -999) < item.rssi { best[ssid] = item }
        }
        return best.values.sorted { $0.rssi > $1.rssi }
    }

    /// Joins with the password macOS already keeps for known networks when `password` is nil.
    nonisolated static func join(_ ssid: String, password: String?) -> Bool {
        guard let iface = CWWiFiClient.shared().interface(),
              let net = (try? iface.scanForNetworks(withName: ssid))?.first else { return false }
        do {
            try iface.associate(to: net, password: password)
            return true
        } catch {
            return false
        }
    }
}
