import Darwin
import Foundation
import SystemConfiguration

struct NetworkInfo: Equatable {
    var down = 0.0
    var up = 0.0
    var history: [(down: Double, up: Double)] = []
    var interface: String?
    var kind = "Not Connected"
    var address: String?

    static func == (a: NetworkInfo, b: NetworkInfo) -> Bool {
        a.down == b.down && a.up == b.up && a.interface == b.interface && a.address == b.address
    }

    /// Ring value: log scale, 10 MB/s and up fills it.
    var level: Double {
        let total = down + up
        guard total > 1024 else { return 0 }
        return min(log10(total / 1024) / 4, 1)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bytesPerSecond
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        if unit == 0 { return "0 KB/s" }
        return value < 10 && unit > 1 ? String(format: "%.1f %@", value, units[unit]) : "\(Int(value.rounded())) \(units[unit])"
    }
}

/// Byte counters from the routing socket's 64-bit interface stats, summed over physical interfaces.
final class NetworkMonitor {
    private var last: (time: TimeInterval, down: UInt64, up: UInt64)?
    private var info = NetworkInfo()
    private let historyLength = 30

    func sample() -> NetworkInfo {
        let (down, up) = Self.counters()
        let now = ProcessInfo.processInfo.systemUptime
        if let last, now > last.time {
            let dt = now - last.time
            info.down = Double(down &- last.down) / dt
            info.up = Double(up &- last.up) / dt
            if down < last.down || up < last.up { info.down = 0; info.up = 0 }
        }
        last = (now, down, up)
        info.history.append((info.down, info.up))
        if info.history.count > historyLength { info.history.removeFirst(info.history.count - historyLength) }
        let primary = Self.primaryInterface()
        info.interface = primary
        info.address = primary.flatMap(Self.ipv4)
        if let primary {
            info.kind = primary == WiFi.shared.interface?.interfaceName ? "Wi-Fi" : primary.hasPrefix("en") ? "Ethernet" : primary.hasPrefix("utun") ? "VPN" : primary
        } else {
            info.kind = "Not Connected"
        }
        return info
    }

    private static func counters() -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return (0, 0) }
        var down: UInt64 = 0
        var up: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let msg = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(msg.ifm_index), &name) != nil {
                        let ifname = String(decoding: name.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
                        if ifname.hasPrefix("en") {
                            down &+= msg.ifm_data.ifi_ibytes
                            up &+= msg.ifm_data.ifi_obytes
                        }
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (down, up)
    }

    private static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Twofold" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else { return nil }
        return value["PrimaryInterface"] as? String
    }

    private static func ipv4(_ interface: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard String(cString: ifa.ifa_name) == interface, let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(decoding: host.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
            }
        }
        return nil
    }
}
