import CoreAudio
import Foundation

nonisolated enum AudioDirection: String, CaseIterable, Identifiable {
    case output, input
    var id: Self { self }
    var title: String { self == .output ? String(localized: "Output") : String(localized: "Input") }
    var scope: AudioObjectPropertyScope { self == .output ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput }
    var defaultSelector: AudioObjectPropertySelector {
        self == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
    }
}

nonisolated struct AudioDeviceInfo: Identifiable {
    let id: AudioDeviceID
    let name: String
}

nonisolated struct AudioChannelState {
    var devices: [AudioDeviceInfo] = []
    var selected: AudioDeviceID = 0
    var volume: Float32?
    var muted: Bool?
}

nonisolated enum AudioControlError: LocalizedError {
    case unavailable, unsupported, failed(OSStatus)
    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "The audio device is no longer available.")
        case .unsupported: String(localized: "This audio device does not support this control.")
        case .failed(let status): String(localized: "Audio operation failed (\(status)).")
        }
    }
}

@MainActor
final class AudioController {
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    private func address(_ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func read<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, initial: T) throws -> T {
        var address = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { throw AudioControlError.failed(status) }
        return value
    }

    private func writable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var result = DarwinBoolean(false)
        return AudioObjectHasProperty(object, &address)
            && AudioObjectIsPropertySettable(object, &address, &result) == noErr && result.boolValue
    }

    private func write<T>(_ value: T, to object: AudioObjectID, address: AudioObjectPropertyAddress) throws {
        guard writable(object, address) else { throw AudioControlError.unsupported }
        var address = address
        var value = value
        let status = withUnsafePointer(to: &value) {
            AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        }
        guard status == noErr else { throw AudioControlError.failed(status) }
    }

    func snapshot(_ direction: AudioDirection) throws -> AudioChannelState {
        var devicesAddress = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(system, &devicesAddress, 0, nil, &size)
        guard status == noErr else { throw AudioControlError.failed(status) }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        if !ids.isEmpty {
        status = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &devicesAddress, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { throw AudioControlError.failed(status) }
        }
        var state = AudioChannelState()
        for id in ids {
            var streams = address(kAudioDevicePropertyStreams, scope: direction.scope)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { continue }
            let name: CFString = try read(id, address(kAudioObjectPropertyName), initial: "" as CFString)
            state.devices.append(AudioDeviceInfo(id: id, name: name as String))
        }
        state.devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        state.selected = try read(system, address(direction.defaultSelector), initial: AudioDeviceID(0))
        guard state.selected != 0 else { return state }
        let volumeAddress = address(kAudioDevicePropertyVolumeScalar, scope: direction.scope)
        if writable(state.selected, volumeAddress) {
            state.volume = try read(state.selected, volumeAddress, initial: Float32(0))
        }
        let muteAddress = address(kAudioDevicePropertyMute, scope: direction.scope)
        if writable(state.selected, muteAddress) {
            state.muted = try read(state.selected, muteAddress, initial: UInt32(0)) != 0
        }
        return state
    }

    func select(_ device: AudioDeviceID, direction: AudioDirection) throws {
        guard try snapshot(direction).devices.contains(where: { $0.id == device }) else { throw AudioControlError.unavailable }
        try write(device, to: system, address: address(direction.defaultSelector))
        guard try snapshot(direction).selected == device else { throw AudioControlError.unavailable }
    }

    func setVolume(_ volume: Float32, direction: AudioDirection, device: AudioDeviceID) throws {
        guard try snapshot(direction).selected == device else { throw AudioControlError.unavailable }
        try write(min(1, max(0, volume)), to: device,
                  address: address(kAudioDevicePropertyVolumeScalar, scope: direction.scope))
    }

    func toggleMute(_ direction: AudioDirection) throws {
        let state = try snapshot(direction)
        guard let muted = state.muted else { throw AudioControlError.unsupported }
        try write(UInt32(muted ? 0 : 1), to: state.selected,
                  address: address(kAudioDevicePropertyMute, scope: direction.scope))
    }

    func observe(_ states: [AudioDirection: AudioChannelState], onChange: @escaping @MainActor () -> Void) throws {
        stopObserving()
        var properties = [(system, address(kAudioHardwarePropertyDevices))]
        for direction in AudioDirection.allCases {
            properties.append((system, address(direction.defaultSelector)))
            if let device = states[direction]?.selected, device != 0 {
                for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                    var property = address(selector, scope: direction.scope)
                    if AudioObjectHasProperty(device, &property) { properties.append((device, property)) }
                }
            }
        }
        for (object, property) in properties {
            var property = property
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor in onChange() }
            }
            let status = AudioObjectAddPropertyListenerBlock(object, &property, .main, block)
            guard status == noErr else { stopObserving(); throw AudioControlError.failed(status) }
            listeners.append((object, property, block))
        }
    }

    func stopObserving() {
        for (object, property, block) in listeners {
            var property = property
            AudioObjectRemovePropertyListenerBlock(object, &property, .main, block)
        }
        listeners.removeAll()
    }
}
