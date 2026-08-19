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

    private static func read() -> Float? {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &deviceSize, &device
        ) == noErr else { return nil }

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
