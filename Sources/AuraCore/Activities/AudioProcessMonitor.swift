import AppKit
import CoreAudio
import Darwin

/// Кто прямо сейчас воспроизводит звук.
///
/// Использует публичный список аудио-процессов CoreAudio (macOS 14.4+).
/// Это единственный способ узнать про *любой* источник — браузер, мессенджер,
/// игру, — потому что приватный MediaRemote, который знает про всё, отдаёт
/// данные только платформенным бинарям Apple.
///
/// Список сам по себе врёт в обе стороны, и обе лечатся здесь:
/// - браузеры играют не из себя, а из вспомогательного процесса, и без
///   подъёма к внешнему бандлу Chrome выглядит как «Google Chrome Helper»
///   или не находится вовсе;
/// - `kAudioProcessPropertyIsRunningOutput` отвечает «да» и тем, кто просто
///   держит открытый поток вывода и молчит в него. Кто из них правда звучит,
///   решает `AudioLevelProbe` — здесь только раскладка по важности.
enum AudioProcessMonitor {
    /// Перебор всех аудио-объектов системы стоит заметно дороже, чем кажется,
    /// а состав играющих приложений меняется медленно.
    private nonisolated(unsafe) static var cache: (sources: [Source], at: Date)?
    /// Три секунды, а не полторы: при раскрытой панели плеер опрашивается
    /// раз в полторы секунды, и кэш ровно к этому моменту протухал — то есть
    /// не работал вовсе. Смену трека кэш не задерживает: рассылка плеера
    /// сбрасывает его сама.
    private static let cacheLifetime: TimeInterval = 3

    struct Source: Equatable {
        /// Объект аудио-процесса: по нему создаётся тап для прослушивания.
        let objectID: AudioObjectID
        let pid: pid_t
        let bundleID: String?
        let name: String
        let kind: Kind

        /// Насколько источник похож на то, ради чего смотрят в вырез.
        ///
        /// Порядок не косметический: приложение, для которого звук — основная
        /// работа, важнее того, которое держит поток на всякий случай.
        enum Kind: Int, Comparable {
            /// Служебный процесс без собственного окна.
            case helper = 0
            /// Обычное приложение: мессенджер, редактор, игра.
            case application = 1
            case browser = 2
            /// Плеер: звук — его работа.
            case player = 3

            static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
        }

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

    /// Приложения, для которых звук — основная работа.
    private static let playerBundleIDs: Set<String> = [
        "com.spotify.client",
        "com.apple.Music",
        "com.apple.TV",
        "com.apple.Podcasts",
        "com.apple.QuickTimePlayerX",
        "org.videolan.vlc",
        "com.colliderli.iina",
        "ru.yandex.desktop.yandex-music",
        "com.deezer.deezer-desktop",
        "com.apple.iTunes",
    ]

    private static let ignoredBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.PowerChime",
        "com.apple.SiriNCService",
        "dev.kekch.aura",
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

    /// Сбрасывает кэш: после смены трека или команды плееру ждать полторы
    /// секунды нечего.
    static func invalidateCache() {
        cache = nil
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

        // Одно приложение может держать несколько играющих процессов —
        // у браузера это отдельный процесс на вкладку. В вырезе оно одно.
        var seen = Set<String>()
        return objects.compactMap(source(for:)).filter { source in
            guard let bundleID = source.bundleID else { return true }
            return seen.insert(bundleID).inserted
        }
    }

    private static func source(for object: AudioObjectID) -> Source? {
        guard isRunningOutput(object), let pid = pid(of: object) else { return nil }

        let process = NSRunningApplication(processIdentifier: pid)
        // Путь к бандлу берём у процесса, а если он не зарегистрирован
        // в LaunchServices — прямо из ядра.
        let location = process?.bundleURL ?? executableURL(pid: pid)
        let applicationURL = location.flatMap(outermostApplication)

        let bundleID = applicationURL
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
            ?? process?.bundleIdentifier
        guard let bundleID, !ignoredBundleIDs.contains(bundleID) else { return nil }

        // Владелец — то приложение, которое видит пользователь: у него имя,
        // иконка и окно. Вспомогательный процесс ничего из этого не имеет.
        let owner = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        let name = owner?.localizedName
            ?? applicationURL.map { FileManager.default.displayName(atPath: $0.path) }
            ?? process?.localizedName
            ?? bundleID

        return Source(
            objectID: object,
            pid: owner?.processIdentifier ?? pid,
            bundleID: bundleID,
            name: name,
            kind: kind(bundleID: bundleID, owner: owner, isBundled: applicationURL != nil)
        )
    }

    private static func kind(
        bundleID: String,
        owner: NSRunningApplication?,
        isBundled: Bool
    ) -> Source.Kind {
        if playerBundleIDs.contains(bundleID) { return .player }
        if BrowserTitleReader.isBrowser(bundleID) { return .browser }
        // Приложение с иконкой в Dock — это то, что пользователь открывал сам.
        if owner?.activationPolicy == .regular { return .application }
        // Само приложение может не значиться запущенным: бывает, что звук
        // идёт только из вложенного помощника. Бандл `.app` при этом есть,
        // и считать такой источник служебным неправильно.
        if owner == nil, isBundled { return .application }
        return .helper
    }

    /// Внешний бандл `.app` из пути к исполняемому файлу.
    ///
    /// `…/Google Chrome.app/Contents/Frameworks/…/Google Chrome Helper.app/…`
    /// сворачивается в `…/Google Chrome.app`: берётся первый `.app` в пути,
    /// а не последний, потому что вложенные — это и есть помощники.
    static func outermostApplication(_ url: URL) -> URL? {
        let components = url.pathComponents
        guard components.first == "/",
              let index = components.firstIndex(where: { $0.hasSuffix(".app") })
        else { return nil }
        return URL(fileURLWithPath: "/" + components[1...index].joined(separator: "/"))
    }

    private static func executableURL(pid: pid_t) -> URL? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = String(decoding: buffer[..<Int(length)], as: UTF8.self)
        return URL(fileURLWithPath: path)
    }

    /// Кого показывать в вырезе. Плеер важнее браузера, браузер важнее
    /// мессенджера, и всё это важнее системного посредника AirPlay.
    static func preferred(from sources: [Source]) -> Source? {
        ranked(sources).first ?? sources.first
    }

    /// Источники по убыванию важности; AirPlay уходит в конец.
    static func ranked(_ sources: [Source]) -> [Source] {
        sources.sorted { lhs, rhs in
            if lhs.isAirPlay != rhs.isAirPlay { return rhs.isAirPlay }
            return lhs.kind > rhs.kind
        }
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
