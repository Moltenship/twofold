import Foundation
import IOKit
import IOKit.ps

struct BatteryInfo: Equatable {
    var present = false
    var level = 0.0
    var charging = false
    var pluggedIn = false
    var fullyCharged = false
    /// Minutes, when macOS has an estimate.
    var minutesLeft: Int?
    var lowPowerMode = false
    var maxCapacity: Int?
    var cycleCount: Int?
    var showPercentage = false

    var stateText: String {
        guard present else { return "No Battery" }
        if charging { return "Charging" }
        if fullyCharged { return "Fully Charged" }
        return pluggedIn ? "Not Charging" : "On Battery"
    }

    var timeText: String? {
        guard let m = minutesLeft, m > 0 else { return nil }
        let text = m >= 60 ? "\(m / 60):\(String(format: "%02d", m % 60))" : "\(m) min"
        return charging ? "\(text) until full" : "\(text) remaining"
    }

    static func read() -> BatteryInfo {
        var info = BatteryInfo()
        info.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        info.showPercentage = CFPreferencesCopyValue("BatteryShowPercentage" as CFString, "com.apple.controlcenter" as CFString,
                                                     kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Bool ?? false
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            info.present = true
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = max(desc[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            info.level = Double(current) / Double(max)
            info.charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            info.pluggedIn = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            info.fullyCharged = desc[kIOPSIsChargedKey] as? Bool ?? false
            let minutes = desc[info.charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
            info.minutesLeft = (minutes ?? -1) > 0 && (info.charging || !info.pluggedIn) ? minutes : nil
        }
        guard info.present else { return info }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return info }
        defer { IOObjectRelease(service) }
        func prop(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        // Newer Macs keep the capacities only inside BatteryData.
        let data = prop("BatteryData") as? [String: Any] ?? [:]
        func int(_ key: String) -> Int? { prop(key) as? Int ?? data[key] as? Int }
        info.cycleCount = int("CycleCount")
        if let raw = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity"), let design = int("DesignCapacity"), design > 0 {
            info.maxCapacity = min(100, Int((Double(raw) / Double(design) * 100).rounded()))
        }
        return info
    }
}
