import AppKit
import CoreAudio
import AudioToolbox

/// Core Audio is observed only while the Music pane is on screen.
@MainActor
final class AudioOutputStore: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String
    }
    @Published private(set) var devices: [Device] = []
    @Published private(set) var selected: AudioDeviceID = 0
    @Published private(set) var volume: Double?
    @Published private(set) var failure: String?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }
    private static func global(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private var isActive = false
    func start() { isActive = true; refresh() }
    func stop() { isActive = false; clearListeners() }
    private func clearListeners() {
        for (object, address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        listeners.removeAll()
    }
    func refresh() {
        guard isActive else { return }
        clearListeners()
        var address = Self.global(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr { selected = device }
        var listAddress = Self.global(kAudioHardwarePropertyDevices)
        var bytes: UInt32 = 0
        if AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &bytes) == noErr, bytes > 0 {
            var ids = [AudioDeviceID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioDeviceID>.size)
            let status = ids.withUnsafeMutableBytes { buffer in
                AudioObjectGetPropertyData(system, &listAddress, 0, nil, &bytes, buffer.baseAddress!)
            }
            if status == noErr { devices = ids.compactMap(Self.outputDevice).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        }
        readVolume()
        observe(system, Self.global(kAudioHardwarePropertyDevices))
        observe(system, Self.global(kAudioHardwarePropertyDefaultOutputDevice))
        if selected != 0 { observe(selected, Self.volumeAddress) }
    }
    private func observe(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                if object == self.system { self.refresh() } else { self.readVolume() }
            }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            listeners.append((object, address, block))
        }
    }
    private static func outputDevice(_ id: AudioDeviceID) -> Device? {
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &size) == noErr, size > 0 else { return nil }
        var address = global(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let name else { return nil }
        // Core Audio transfers ownership of CF-valued properties to the caller.
        return Device(id: id, name: name.takeRetainedValue() as String)
    }
    func select(_ id: AudioDeviceID) {
        guard devices.contains(where: { $0.id == id }) else { return }
        var id = id
        var address = Self.global(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        failure = status == noErr ? nil : localized("Could not switch audio output. Try Sound Settings.")
        refresh()
    }
    private func readVolume() {
        var address = Self.volumeAddress
        var settable = DarwinBoolean(false)
        guard selected != 0, AudioObjectIsPropertySettable(selected, &address, &settable) == noErr, settable.boolValue else {
            volume = nil; return
        }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        volume = AudioObjectGetPropertyData(selected, &address, 0, nil, &size, &value) == noErr ? Double(value) : nil
    }
    func setVolume(_ value: Double) {
        guard volume != nil, value.isFinite else { return }
        var address = Self.volumeAddress
        var scalar = Float32(min(max(value, 0), 1))
        let status = AudioObjectSetPropertyData(selected, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar)
        if status == noErr { volume = Double(scalar) }
        else { failure = localized("Use the volume controls on this device.") }
    }
}
