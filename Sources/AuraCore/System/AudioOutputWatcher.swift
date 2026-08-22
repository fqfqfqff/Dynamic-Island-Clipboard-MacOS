import CoreAudio
import Foundation

/// Следит за тем, куда уходит звук, и замечает отключение наушников.
///
/// macOS ставит на паузу сама — но только приложения, которые об этом
/// позаботились. Spotify так делает, браузер обычно нет: выдернул наушники —
/// и вагон метро слушает вместе с вами.
///
/// Отличить отключение от подключения можно по способу подключения нового
/// устройства вывода: звук вернулся на встроенные динамики — значит, то,
/// что было до них, отсоединили.
@MainActor
final class AudioOutputWatcher {
    /// Наушники отсоединили — звук ушёл на встроенные динамики.
    var onHeadphonesRemoved: (() -> Void)?

    private var isListening = false
    private var wasExternal = false

    private static var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard !isListening else { return }
        wasExternal = Self.isExternalOutput()

        // Слушаем событие, а не опрашиваем: смена устройства вывода бывает
        // пару раз в день, а таймер работал бы всё время.
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.deviceChanged() }
        }

        isListening = status == noErr
    }

    func stop() {
        guard isListening else { return }
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.address,
            DispatchQueue.main
        ) { _, _ in }
        isListening = false
    }

    private func deviceChanged() {
        let isExternal = Self.isExternalOutput()
        defer { wasExternal = isExternal }

        // Интересует один переход: было внешнее — стало встроенное.
        // Обратный — это подключение, и останавливать музыку там незачем.
        guard wasExternal, !isExternal else { return }
        onHeadphonesRemoved?()
    }

    // MARK: - Куда идёт звук

    /// Внешнее ли устройство вывода: наушники, колонка, монитор.
    static func isExternalOutput() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        return !isBuiltIn(device)
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func isBuiltIn(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr
        else { return true }

        return transport == kAudioDeviceTransportTypeBuiltIn
    }
}
