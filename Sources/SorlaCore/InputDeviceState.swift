import CoreAudio
import Foundation

public struct InputDeviceState: Equatable, Sendable {
    public var isMuted: Bool?
    public var volume: Float?

    public init(isMuted: Bool? = nil, volume: Float? = nil) {
        self.isMuted = isMuted
        self.volume = volume
    }

    // A property the device doesn't report is unknown, never muted.
    public var seemsMuted: Bool {
        isMuted == true || volume == 0
    }

    // Devices expose mute and volume on the main element, per channel, or not at all.
    public static func combinedMute(main: Bool?, channels: [Bool?]) -> Bool? {
        if let main { return main }
        let known = channels.compactMap { $0 }
        return known.isEmpty ? nil : known.allSatisfy { $0 }
    }

    public static func combinedVolume(main: Float?, channels: [Float?]) -> Float? {
        main ?? channels.compactMap { $0 }.max()
    }
}

public protocol InputDeviceStateReading: Sendable {
    func currentState() -> InputDeviceState
}

public struct CoreAudioInputDeviceState: InputDeviceStateReading {
    public init() {}

    public func currentState() -> InputDeviceState {
        guard let device = Self.defaultInputDevice() else { return InputDeviceState() }
        let channels = (0..<Self.inputChannelCount(of: device)).map { AudioObjectPropertyElement($0 + 1) }
        let mute: (AudioObjectPropertyElement) -> Bool? = { element in
            Self.read(UInt32.self, kAudioDevicePropertyMute, of: device, element: element).map { $0 != 0 }
        }
        let volume: (AudioObjectPropertyElement) -> Float? = { element in
            Self.read(Float32.self, kAudioDevicePropertyVolumeScalar, of: device, element: element)
        }
        return InputDeviceState(
            isMuted: InputDeviceState.combinedMute(main: mute(kAudioObjectPropertyElementMain), channels: channels.map(mute)),
            volume: InputDeviceState.combinedVolume(main: volume(kAudioObjectPropertyElementMain), channels: channels.map(volume))
        )
    }

    private static func defaultInputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func inputChannelCount(of device: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func read<Value>(
        _ type: Value.Type,
        _ selector: AudioObjectPropertySelector,
        of device: AudioObjectID,
        element: AudioObjectPropertyElement
    ) -> Value? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var size = UInt32(MemoryLayout<Value>.size)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<Value>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr,
              size == UInt32(MemoryLayout<Value>.size)
        else { return nil }
        return storage.load(as: Value.self)
    }
}
