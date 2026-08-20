import AudioToolbox
import CoreAudio

/// Текущая громкость системы. Нужна, чтобы полоски эквалайзера не жили своей
/// жизнью, а хотя бы отражали, насколько громко играет звук.
enum SystemVolume {
    @MainActor
    private static var cached: (value: Float, at: Date)?

    @MainActor
    static var current: Float {
        if let cached, Date().timeIntervalSince(cached.at) < 2 {
            return cached.value
        }
        let value = read() ?? 0.5
        cached = (value, Date())
        return value
    }

    /// Ставит громкость. Значение подрезается: система принимает 0…1,
    /// а на краях иначе легко проскочить в тишину или в максимум.
    @MainActor
    static func set(_ value: Float) {
        guard let device = outputDevice() else { return }
        var volume = max(0, min(1, value))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume
        )
        cached = (volume, Date())
    }

    private static func outputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        ) == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func read() -> Float? {
        guard let device = outputDevice() else { return nil }

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume) == noErr
        else { return nil }
        return volume
    }
}
