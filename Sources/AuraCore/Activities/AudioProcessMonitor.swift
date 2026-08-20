import AppKit
import CoreAudio

/// Кто прямо сейчас воспроизводит звук.
///
/// Использует публичный список аудио-процессов CoreAudio (macOS 14.4+).
/// Это единственный способ узнать про *любой* источник — браузер, мессенджер,
/// игру, — потому что приватный MediaRemote, который знает про всё, отдаёт
/// данные только платформенным бинарям Apple.
enum AudioProcessMonitor {
    /// Перебор всех аудио-объектов системы стоит заметно дороже, чем кажется,
    /// а состав играющих приложений меняется медленно.
    private nonisolated(unsafe) static var cache: (sources: [Source], at: Date)?
    private static let cacheLifetime: TimeInterval = 1.5

    struct Source: Equatable {
        let pid: pid_t
        let bundleID: String?
        let name: String

        var icon: NSImage? {
            NSRunningApplication(processIdentifier: pid)?.icon
        }

        /// Звук пришёл с другого устройства по AirPlay — с телефона или планшета.
        ///
        /// Это единственный способ показать в вырезе музыку с айфона: когда
        /// он транслирует на Mac, звук действительно проходит через нашу
        /// звуковую подсистему, и его видно наравне с local-приложениями.
        /// Просто играющий рядом телефон Mac не видит никак.
        var isAirPlay: Bool {
            guard let bundleID else { return false }
            return AudioProcessMonitor.airPlayBundleIDs.contains(bundleID)
        }
    }

    static let airPlayBundleIDs: Set<String> = [
        "com.apple.AirPlayUIAgent",
        "com.apple.AirPlayXPCHelper",
        "com.apple.sharingd",
        "com.apple.controlcenter",
    ]

    /// Приложения, чей звук идёт на выход прямо сейчас.
    static func playingSources() -> [Source] {
        if let cache, Date().timeIntervalSince(cache.at) < cacheLifetime {
            return cache.sources
        }
        let sources = readSources()
        cache = (sources, Date())
        return sources
    }

    private static func readSources() -> [Source] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects
        ) == noErr else { return [] }

        return objects.compactMap(source(for:))
    }

    private static func source(for object: AudioObjectID) -> Source? {
        guard isRunningOutput(object) else { return nil }
        guard let pid = pid(of: object) else { return nil }

        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        // Системные звуки и служебные процессы плеером не считаем.
        guard let bundleID = app.bundleIdentifier,
              !ignoredBundleIDs.contains(bundleID) else { return nil }

        return Source(
            pid: pid,
            bundleID: bundleID,
            name: app.localizedName ?? bundleID
        )
    }

    private static let ignoredBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.PowerChime",
        "com.apple.SiriNCService",
        "dev.kekch.aura",
    ]

    /// Приложение, играющее само, важнее системного посредника: если звучит
    /// и Spotify, и AirPlay, показать нужно Spotify.
    static func preferred(from sources: [Source]) -> Source? {
        sources.first { !$0.isAirPlay } ?? sources.first
    }

    private static func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
        else { return false }
        return value == 1
    }

    private static func pid(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr
        else { return nil }
        return pid
    }
}
