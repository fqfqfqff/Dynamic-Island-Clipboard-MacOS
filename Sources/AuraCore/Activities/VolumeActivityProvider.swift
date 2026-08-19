import AudioToolbox
import CoreAudio
import SwiftUI

/// Показывает громкость в вырезе — как на iPhone, только у нас это ещё и
/// удобнее: индикатор оказывается рядом с тем местом, куда и так смотришь.
///
/// Системный HUD посреди экрана при этом никуда не денется: спрятать его
/// можно только выгрузив системный процесс, а это Aura делать не станет.
@MainActor
final class VolumeActivityProvider {
    private let center: ActivityCenter
    private var deviceID = AudioDeviceID(kAudioObjectUnknown)
    private var lastVolume: Float?
    private var lastMuted: Bool?
    private let activityID = "system.volume"

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    init(center: ActivityCenter) {
        self.center = center
    }

    private var listener: AudioObjectPropertyListenerBlock?

    func stop() {
        guard let listener, deviceID != kAudioObjectUnknown else { return }
        AudioObjectRemovePropertyListenerBlock(deviceID, &volumeAddress, .main, listener)
        AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddress, .main, listener)
        self.listener = nil
        center.remove(id: activityID)
    }

    func start() {
        stop()
        guard let device = Self.defaultOutputDevice() else {
            NSLog("Aura: устройство вывода не найдено, громкость показываться не будет")
            return
        }
        deviceID = device

        // Первое чтение только запоминает состояние: показывать активность
        // при запуске приложения незачем.
        lastVolume = readVolume()
        lastMuted = readMuted()

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.changed() }
            }
        }
        self.listener = listener

        AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, .main, listener)
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, .main, listener)
    }

    private func changed() {
        let volume = readVolume()
        let muted = readMuted()
        defer {
            lastVolume = volume
            lastMuted = muted
        }

        guard volume != lastVolume || muted != lastMuted else { return }

        let percent = Int(round((volume ?? 0) * 100))
        let isMuted = muted ?? false

        center.upsert(
            Activity(
                id: activityID,
                title: isMuted ? "Без звука" : "Громкость",
                subtitle: isMuted ? nil : "\(percent)%",
                symbol: symbol(for: isMuted ? 0 : (volume ?? 0), muted: isMuted),
                tint: .white,
                priority: .important,
                indicator: .progress(isMuted ? 0 : Double(volume ?? 0)),
                expiresAt: Date().addingTimeInterval(1.6)
            )
        )
    }

    private func symbol(for volume: Float, muted: Bool) -> String {
        if muted || volume == 0 { return "speaker.slash.fill" }
        if volume < 0.33 { return "speaker.wave.1.fill" }
        if volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func readVolume() -> Float? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private func readMuted() -> Bool? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &value)
        return status == noErr ? value == 1 : nil
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }
}
