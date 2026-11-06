import AudioToolbox
import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    var id: AudioObjectID
    var name: String
    var transport: UInt32

    var symbol: String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            SystemState.shared.bluetooth.devices.first { $0.name == name }?.symbol ?? headphonesSymbol(name)
        case kAudioDeviceTransportTypeAirPlay: "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: "tv"
        case kAudioDeviceTransportTypeUSB: "cable.connector"
        default: "hifispeaker"
        }
    }
}

/// The SF Symbol for a pair of headphones: by Apple product ID when there is one, else guessed from the name.
func headphonesSymbol(_ name: String, productID: Int = 0) -> String {
    switch productID {
    case 0x2002, 0x200F: return "airpods"
    case 0x2013: return "airpods.gen3"
    case 0x2019, 0x201B: return "airpods.gen4"
    case 0x200E, 0x2014, 0x2024, 0x2027: return "airpods.pro"
    case 0x200A, 0x201F: return "airpods.max"
    case 0x200B, 0x201D: return "beats.powerbeats.pro"
    case 0x2011, 0x2016: return "beats.studiobuds"
    case 0x2012: return "beats.fitpro"
    case 0x2006, 0x2009, 0x200C, 0x2017, 0x2025: return "beats.headphones"
    default: break
    }
    let n = name.lowercased()
    return if n.contains("airpods max") { "airpods.max" }
    else if n.contains("airpods pro") { "airpods.pro" }
    else if n.contains("airpods") { "airpods" }
    else if n.contains("beats") { "beats.headphones" }
    else { "headphones" }
}

struct AudioInfo: Equatable {
    var volume = 0.0
    var muted = false
    var output: AudioDevice?
    var outputs: [AudioDevice] = []
    var hasVolume = false

    var symbol: String {
        if muted || volume == 0 { return "speaker.slash.fill" }
        switch volume {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

/// The default output device through CoreAudio. Listeners call `onChange` on the main thread.
final class Audio {
    static let shared = Audio()
    var onChange: (() -> Void)?
    private var watched: AudioObjectID = 0

    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func get<T: BitwiseCopyable>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ initial: T) -> T? {
        var addr = addr
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectHasProperty(object, &addr),
              AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func set<T: BitwiseCopyable>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ value: T) {
        var addr = addr
        var value = value
        AudioObjectSetPropertyData(object, &addr, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }

    private var defaultOutput: AudioObjectID {
        Self.get(AudioObjectID(kAudioObjectSystemObject), Self.address(kAudioHardwarePropertyDefaultOutputDevice), AudioObjectID(0)) ?? 0
    }

    private static let volumeAddress = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput)
    private static let muteAddress = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)

    func start() {
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.watchDefault()
                self?.onChange?()
            }
        }
        watchDefault()
    }

    private func watchDefault() {
        let device = defaultOutput
        guard device != watched, device != 0 else { return }
        watched = device
        for var addr in [Self.volumeAddress, Self.muteAddress] {
            AudioObjectAddPropertyListenerBlock(device, &addr, .main) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, self.watched == device else { return }
                    self.onChange?()
                }
            }
        }
    }

    func read() -> AudioInfo {
        var info = AudioInfo()
        let device = defaultOutput
        if let v: Float32 = Self.get(device, Self.volumeAddress, Float32(0)) {
            info.volume = Double(v)
            info.hasVolume = true
        }
        info.muted = (Self.get(device, Self.muteAddress, UInt32(0)) ?? 0) != 0
        info.outputs = Self.outputDevices()
        info.output = info.outputs.first { $0.id == device }
        return info
    }

    func setVolume(_ value: Double) {
        let device = defaultOutput
        Self.set(device, Self.volumeAddress, Float32(min(max(value, 0), 1)))
        if value > 0, (Self.get(device, Self.muteAddress, UInt32(0)) ?? 0) != 0 {
            Self.set(device, Self.muteAddress, UInt32(0))
        }
    }

    func setMuted(_ muted: Bool) {
        Self.set(defaultOutput, Self.muteAddress, UInt32(muted ? 1 : 0))
    }

    func setOutput(_ id: AudioObjectID) {
        Self.set(AudioObjectID(kAudioObjectSystemObject), Self.address(kAudioHardwarePropertyDefaultOutputDevice), id)
    }

    private static func outputDevices() -> [AudioDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            var nameAddr = address(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, &name) == noErr,
                  let cf = name?.takeRetainedValue() else { return nil }
            let transport: UInt32 = get(id, address(kAudioDevicePropertyTransportType), UInt32(0)) ?? 0
            // Aggregate and virtual devices clutter the list the way Sound settings doesn't.
            if transport == kAudioDeviceTransportTypeAggregate || transport == kAudioDeviceTransportTypeVirtual { return nil }
            return AudioDevice(id: id, name: cf as String, transport: transport)
        }
    }
}
