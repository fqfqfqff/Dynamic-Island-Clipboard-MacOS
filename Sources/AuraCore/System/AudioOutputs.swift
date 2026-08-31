import CoreAudio
import Foundation

/// Список устройств вывода и переключение между ними.
///
/// В macOS смена вывода — это Пункт управления или ⌥-клик по значку звука:
/// два движения и всплывающая панель поверх всего. Вырез уже знает, куда
/// идёт звук, — переключать оттуда естественнее.
@MainActor
enum AudioOutputs {
    struct Device: Identifiable, Equatable {
        let id: AudioObjectID
        let name: String
        let isCurrent: Bool
    }

    /// Все устройства, у которых есть выход. Микрофоны и виртуальные
    /// входы сюда не попадают.
    static func list() -> [Device] {
        let current = currentID()
        return allDeviceIDs()
            .filter { hasOutput($0) }
            .compactMap { id in
                guard let name = name(of: id) else { return nil }
                return Device(id: id, name: name, isCurrent: id == current)
            }
    }

    static func current() -> Device? {
        list().first { $0.isCurrent }
    }

    /// Переключить вывод. Возвращает, получилось ли.
    @discardableResult
    static func select(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)

        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &device
        ) == noErr
    }

    // MARK: - CoreAudio

    private static func currentID() -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return device
    }

    private static func allDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids
    }

    /// Есть ли у устройства выходные каналы.
    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size > 0 else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }

        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr
        else { return false }

        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func name(of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)

        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr
        else { return nil }

        let text = name as String
        return text.isEmpty ? nil : text
    }
}
