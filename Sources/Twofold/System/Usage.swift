import AppKit
import Darwin
import IOKit.pwr_mgt

struct MemoryInfo: Equatable {
    var total: UInt64 = ProcessInfo.processInfo.physicalMemory
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0

    var used: UInt64 { app + wired + compressed }
    var level: Double { total > 0 ? min(Double(used) / Double(total), 1) : 0 }

    /// The split Activity Monitor shows.
    static func read() -> MemoryInfo {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var info = MemoryInfo()
        guard result == KERN_SUCCESS else { return info }
        let page = UInt64(sysconf(_SC_PAGESIZE))
        let purgeable = UInt64(stats.purgeable_count)
        info.app = (UInt64(stats.internal_page_count) - min(purgeable, UInt64(stats.internal_page_count))) * page
        info.wired = UInt64(stats.wire_count) * page
        info.compressed = UInt64(stats.compressor_page_count) * page
        info.cached = (UInt64(stats.external_page_count) + purgeable) * page
        return info
    }
}

struct CPUInfo: Equatable {
    var user = 0.0
    var system = 0.0
    var history: [Double] = []
    var load: [Double] = [0, 0, 0]
    var cores = ProcessInfo.processInfo.activeProcessorCount
    var thermal = ProcessInfo.ThermalState.nominal
    var uptime: TimeInterval = 0

    var level: Double { min(user + system, 1) }
    var idle: Double { max(1 - user - system, 0) }

    var thermalText: String {
        switch thermal {
        case .nominal: "Normal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    var uptimeText: String {
        let minutes = Int(uptime / 60)
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        if days > 0 { return "\(days) day\(days == 1 ? "" : "s"), \(hours) hr" }
        if hours > 0 { return "\(hours) hr, \(mins) min" }
        return "\(mins) min"
    }
}

final class CPUMonitor {
    private var last: host_cpu_load_info?
    private var info = CPUInfo()

    func sample() -> CPUInfo {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            if let last {
                let user = Double(load.cpu_ticks.0 &- last.cpu_ticks.0) + Double(load.cpu_ticks.3 &- last.cpu_ticks.3)
                let system = Double(load.cpu_ticks.1 &- last.cpu_ticks.1)
                let idle = Double(load.cpu_ticks.2 &- last.cpu_ticks.2)
                let total = user + system + idle
                if total > 0 {
                    info.user = user / total
                    info.system = system / total
                }
            }
            last = load
        }
        info.history.append(info.level)
        if info.history.count > 30 { info.history.removeFirst(info.history.count - 30) }
        var avg = [Double](repeating: 0, count: 3)
        if getloadavg(&avg, 3) == 3 { info.load = avg }
        info.thermal = ProcessInfo.processInfo.thermalState
        info.cores = ProcessInfo.processInfo.activeProcessorCount
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 {
            info.uptime = Date().timeIntervalSince1970 - Double(boot.tv_sec)
        }
        return info
    }
}

struct Volume: Identifiable, Equatable {
    var id: URL { url }
    var url: URL
    var name: String
    var free: Int64
    var total: Int64
    var isRoot: Bool

    var used: Double { total > 0 ? 1 - Double(free) / Double(total) : 0 }
}

struct DiskInfo: Equatable {
    var volumes: [Volume] = []
    var root: Volume? { volumes.first(where: \.isRoot) ?? volumes.first }
    var level: Double { root?.used ?? 0 }

    static func read() -> DiskInfo {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeAvailableCapacityKey, .volumeIsBrowsableKey, .volumeIsLocalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var info = DiskInfo()
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.volumeIsBrowsable == true, v.volumeIsLocal == true,
                  let total = v.volumeTotalCapacity, total > 0 else { continue }
            let free = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
            info.volumes.append(Volume(url: url, name: v.volumeName ?? url.lastPathComponent, free: free, total: Int64(total), isRoot: url.path == "/"))
        }
        return info
    }
}

struct DisplayInfo: Identifiable, Equatable {
    var id: CGDirectDisplayID
    var name: String
    var resolution: String
    var refresh: String?
}

/// Keep Awake holds a display-sleep assertion while it is on.
final class Displays {
    static let shared = Displays()
    private var assertion: IOPMAssertionID = 0
    private(set) var keepAwake = false

    func setKeepAwake(_ on: Bool) {
        if on, !keepAwake {
            keepAwake = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                    "Twofold Keep Awake" as CFString, &assertion) == kIOReturnSuccess
        } else if !on, keepAwake {
            IOPMAssertionRelease(assertion)
            keepAwake = false
        }
    }

    func read() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            let mode = CGDisplayCopyDisplayMode(id)
            let resolution = mode.map { "\($0.width) × \($0.height)" } ?? "\(Int(screen.frame.width)) × \(Int(screen.frame.height))"
            let hz = mode?.refreshRate ?? 0
            let refresh = hz > 0 ? "\(Int(hz.rounded())) Hz" : screen.maximumFramesPerSecond > 0 ? "\(screen.maximumFramesPerSecond) Hz" : nil
            return DisplayInfo(id: id, name: screen.localizedName, resolution: resolution, refresh: refresh)
        }
    }
}

extension UInt64 {
    var gb: String { Int64(self).gb }
}

extension Int64 {
    var gb: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .memory)
    }

    var diskSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
