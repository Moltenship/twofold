import CoreBluetooth
import IOBluetooth
import IOKit

struct BluetoothDevice: Identifiable, Hashable {
    enum Kind { case headphones, audio, keyboard, mouse, phone, computer, watch, other }
    var id: String
    var name: String
    var connected: Bool
    var kind: Kind
    var battery: Int?
    /// Apple's product ID for Apple and Beats devices, 0 otherwise.
    var productID = 0

    var symbol: String {
        switch kind {
        case .headphones: headphonesSymbol(name, productID: productID)
        case .audio: "hifispeaker"
        case .keyboard: "keyboard"
        case .mouse: "computermouse"
        case .phone: "iphone"
        case .computer: "laptopcomputer"
        case .watch: "applewatch"
        case .other: "dot.radiowaves.left.and.right"
        }
    }
}

struct BluetoothInfo: Equatable {
    var powered = false
    var devices: [BluetoothDevice] = []

    var connected: [BluetoothDevice] { devices.filter(\.connected) }

    var valueText: String {
        let c = connected
        if !powered { return "Off" }
        if c.isEmpty { return "No Devices" }
        return c.count == 1 ? c[0].name : "\(c.count) connected"
    }

    /// Lowest battery among connected devices that report one, else 1 when anything is connected.
    var level: Double {
        let c = connected
        if let low = c.compactMap(\.battery).min() { return Double(low) / 100 }
        return c.isEmpty ? 0 : 1
    }
}

final class Bluetooth: NSObject {
    static let shared = Bluetooth()
    /// Called on the main thread with a device that just connected.
    var onConnect: ((BluetoothDevice) -> Void)?
    private var connectNote: IOBluetoothUserNotification?

    /// The first IOBluetooth call raises the permission prompt and blocks its thread until it is answered,
    /// so reads run off the main thread, and only once Bluetooth is on screen or already allowed.
    static var allowed: Bool { CBManager.authorization == .allowedAlways }

    func listen() {
        guard connectNote == nil, Self.allowed else { return }
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onConnect?(Self.describe(device, batteries: Self.hidBatteries()))
    }

    nonisolated static func read() -> BluetoothInfo {
        var info = BluetoothInfo()
        info.powered = IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let batteries = Self.hidBatteries()
        info.devices = paired.map { Self.describe($0, batteries: batteries) }
            .sorted { ($0.connected ? 0 : 1, $0.name) < ($1.connected ? 0 : 1, $1.name) }
        return info
    }

    func toggle(_ id: String) {
        guard let device = IOBluetoothDevice(addressString: id) else { return }
        if device.isConnected() { device.closeConnection() } else { device.openConnection() }
    }

    nonisolated private static func describe(_ d: IOBluetoothDevice, batteries: [String: Int]) -> BluetoothDevice {
        let name = d.name ?? d.addressString ?? "Device"
        let kind: BluetoothDevice.Kind
        switch Int(d.deviceClassMajor) {
        case kBluetoothDeviceClassMajorAudio:
            kind = Int(d.deviceClassMinor) == kBluetoothDeviceClassMinorAudioHeadphones
                || Int(d.deviceClassMinor) == kBluetoothDeviceClassMinorAudioHeadset ? .headphones : .audio
        case kBluetoothDeviceClassMajorPeripheral:
            kind = (Int(d.deviceClassMinor) & 0x10) != 0 ? .keyboard : .mouse
        case kBluetoothDeviceClassMajorPhone: kind = .phone
        case kBluetoothDeviceClassMajorComputer: kind = .computer
        case kBluetoothDeviceClassMajorWearable: kind = .watch
        default: kind = name.localizedCaseInsensitiveContains("airpods") ? .headphones : .other
        }
        // IOBluetoothDevice answers productID and vendorID without declaring them.
        func number(_ key: String) -> Int { d.responds(to: NSSelectorFromString(key)) ? d.value(forKey: key) as? Int ?? 0 : 0 }
        let apple = number("vendorID") == 0x004C
        return BluetoothDevice(id: d.addressString ?? name, name: name, connected: d.isConnected(), kind: kind, battery: batteries[name],
                               productID: apple ? number("productID") : 0)
    }

    /// Battery levels that HID devices (keyboards, mice, trackpads) publish in the IO registry, by product name.
    /// AirPods report theirs only through private API, so they have none here.
    nonisolated private static func hidBatteries() -> [String: Int] {
        var result: [String: Int] = [:]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else { return result }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func prop(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            if let name = prop("Product") as? String, let percent = prop("BatteryPercent") as? Int {
                result[name] = percent
            }
        }
        return result
    }
}
