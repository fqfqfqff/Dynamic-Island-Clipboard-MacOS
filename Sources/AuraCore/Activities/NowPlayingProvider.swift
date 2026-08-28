import AppKit
import SwiftUI

/// Что сейчас звучит — из любого приложения.
///
/// Источник звука определяется через список аудио-процессов CoreAudio, поэтому
/// плеер видит и Spotify, и видео в браузере, и голосовое в мессенджере.
/// Метаданные добираются по возможностям источника:
/// - Музыка и Spotify отвечают по AppleScript полным набором: трек, артист,
///   длительность, позиция, обложка;
/// - браузеры отдают заголовок активной вкладки;
/// - для остальных остаётся имя приложения и его иконка.
@MainActor
final class NowPlayingProvider: ObservableObject {
    struct NowPlaying: Equatable {
        var title: String
        var subtitle: String?
        var appName: String
        /// Альбом: показывается по нажатой ⌥, когда одного названия мало.
        var album: String?
        var artwork: NSImage?
        /// Обложка как её отдал плеер, без уменьшения.
        ///
        /// В вырезе она не нужна — там хватает двухсот точек, — но витрина
        /// во весь экран растягивает эту же картинку до трёхсот с лишним,
        /// и уменьшенная копия там заметно мылит.
        var fullArtwork: NSImage?
        /// Заранее размытая копия обложки для подложки острова.
        var blurredArtwork: NSImage?
        var duration: TimeInterval?
        var elapsed: TimeInterval?
        /// Момент, когда была получена позиция, — между опросами полоса
        /// доводится по часам, иначе она дёргается раз в несколько секунд.
        var elapsedAt: Date = .now
        var isPlaying: Bool
        var accent: Color = .pink
        /// Умеем ли мы этим источником управлять.
        var canControl: Bool

        func progress(at date: Date = .now) -> Double? {
            guard let duration, duration > 0, let elapsed else { return nil }
            let drift = isPlaying ? date.timeIntervalSince(elapsedAt) : 0
            return min(1, max(0, (elapsed + drift) / duration))
        }

        func elapsedNow(at date: Date = .now) -> TimeInterval? {
            guard let elapsed else { return nil }
            let drift = isPlaying ? date.timeIntervalSince(elapsedAt) : 0
            return min(duration ?? .greatestFiniteMagnitude, elapsed + drift)
        }

        func differsMeaningfully(from other: NowPlaying?) -> Bool {
            guard let other else { return true }
            return title != other.title
                || subtitle != other.subtitle
                || isPlaying != other.isPlaying
                || appName != other.appName
                // Сравнение по ссылке: смена одной обложки на другую иначе
                // не считалась изменением, и в вырезе висела картинка от
                // предыдущего трека.
                || artwork !== other.artwork
        }
    }

    enum Command {
        case togglePlayPause
        case next
        case previous
    }

    private struct ScriptablePlayer {
        let bundleID: String
        let scriptName: String
        let durationDivisor: Double
        let hasArtworkURL: Bool
        /// Есть ли у трека идентификатор, по которому можно достать
        /// полный список исполнителей.
        let hasIdentifier: Bool
    }

    private enum ScriptOutcome {
        case success(String)
        case denied
        case failed(Int)
    }

    private let scriptablePlayers = [
        ScriptablePlayer(bundleID: "com.spotify.client", scriptName: "Spotify",
                         durationDivisor: 1000, hasArtworkURL: true, hasIdentifier: true),
        ScriptablePlayer(bundleID: "com.apple.Music", scriptName: "Music",
                         durationDivisor: 1, hasArtworkURL: false, hasIdentifier: false),
    ]

    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var accessDenied = false

    private let center: ActivityCenter
    private let settings: SettingsStore
    private let lyrics: LyricsProvider
    private let activityID = "media.nowplaying"

    private var ticker: Timer?
    private var deniedPlayers: Set<String> = []
    private let runner = AppleScriptRunner()
    private var refreshStartedAt: Date?
    private let refreshTimeout: TimeInterval = 15
    private var artworkCache: (key: String, image: NSImage)?
    /// Исходник обложки — только для витрины, в вырезе он избыточен.
    private var fullArtwork: NSImage?
    private var accentColor: Color = .pink
    private var blurredArtwork: NSImage?
    private var lastArtworkPath: String?
    private var silentPolls = 0
    private var lastSuccess: Date?
    private var lastFailureReason = "опроса ещё не было"
    /// Слушает кандидата, чтобы отличить играющее приложение от того,
    /// которое просто держит открытый поток вывода.
    private let probe = AudioLevelProbe()
    /// Источники, признанные немыми, — ненадолго, иначе прослушивание
    /// каждый раз упиралось бы в одно и то же молчащее приложение.
    private var silentUntil: [pid_t: Date] = [:]
    /// Сколько раз подряд источник признан немым.
    ///
    /// Одного раза мало. Браузер замолкает на доли секунды между сегментами
    /// видео и на стыке рекламы — по одному вердикту карточка исчезала
    /// и возвращалась, и плеер из Chrome мигал.
    private var silentStrikes: [pid_t: Int] = [:]
    private let strikesToDrop = 2
    /// Заголовки вкладок браузеров: читаются асинхронно, показываются сразу.
    private var browserTitles: [String: (title: String, at: Date)] = [:]
    private var playerObservers: [NSObjectProtocol] = []

    /// Плееры сообщают о смене трека сами, и это единственный способ узнать
    /// о ней сразу. Ждать очередного опроса — до четырёх секунд со старой
    /// обложкой в вырезе; именно так это и выглядело. Разрешений рассылка
    /// не требует.
    private static let playerNotifications = [
        "com.spotify.client.PlaybackStateChanged",
        "com.apple.iTunes.playerInfo",
    ]

    init(center: ActivityCenter, settings: SettingsStore, lyrics: LyricsProvider) {
        self.center = center
        self.settings = settings
        self.lyrics = lyrics
    }

    var diagnostics: [String: Any] {
        [
            "источникиЗвука": AudioProcessMonitor.playingSources()
                .map { "\($0.name) [\($0.kind)]" },
            "прослушивание": probe.summary,
            "признаныНемыми": silentUntil.filter { $0.value > Date() }.count,
            "запрещены": Array(deniedPlayers),
            "опросИдёт": refreshStartedAt != nil,
            "последнийУспех": lastSuccess.map { Int(-$0.timeIntervalSinceNow) } ?? -1,
            "последняяПричина": lastFailureReason,
        ]
    }

    /// Когда панель раскрыта, позицию нужно знать точнее — там видна полоса
    /// длительности. В свёрнутом виде хватает редких опросов.
    var isDetailed = false {
        didSet {
            guard isDetailed != oldValue, ticker != nil else { return }
            retime()
        }
    }

    func start() {
        retime()
        observePlayers()
        refresh()
    }

    /// Перевести опрос на другой интервал — и только.
    ///
    /// Раньше здесь звался `start()`, а тот начинался с `stop()`, который
    /// сносит всё: тап уровня, подписки на плееры, активность в вырезе
    /// и сам `nowPlaying`. Происходило это ровно в момент раскрытия панели,
    /// когда режим переключается на подробный.
    ///
    /// Со стороны это и выглядело как подвисание: остров терял содержимое,
    /// высота панели пересчитывалась прямо посреди анимации, спектр глушил
    /// и заново создавал агрегатное устройство CoreAudio — а это десятки
    /// миллисекунд на главном потоке. Потом всё возвращалось.
    ///
    /// Опрос здесь намеренно не запускается: полоса длительности и так
    /// идёт по часам между опросами, а лишняя работа в кадре раскрытия —
    /// именно то, от чего избавляемся.
    private func retime() {
        ticker?.invalidate()

        let interval: TimeInterval = isDetailed ? 1.5 : (settings.showLyrics ? 2 : 4)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func observePlayers() {
        guard playerObservers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()

        playerObservers = Self.playerNotifications.map { name in
            center.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Список аудио-процессов кэшируется на полторы секунды;
                    // на смене трека ждать, пока кэш протухнет, незачем.
                    AudioProcessMonitor.invalidateCache()
                    self.refreshStartedAt = nil
                    self.refresh()
                }
            }
        }
    }

    private func stopObservingPlayers() {
        let center = DistributedNotificationCenter.default()
        playerObservers.forEach(center.removeObserver)
        playerObservers.removeAll()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        stopObservingPlayers()
        probe.stop()
        center.remove(id: activityID)
        nowPlaying = nil
    }

    /// Подставить состояние вручную — для снимков интерфейса и тестов.
    /// Живой опрос при этом не запускается: сцене нужен только результат.
    func inject(_ playing: NowPlaying?) {
        nowPlaying = playing
    }

    func retryAccess() {
        settings.musicAccessBlocked = false
        accessDenied = false
        deniedPlayers.removeAll()
        refresh()
    }

    // MARK: - Управление

    func send(_ command: Command) {
        if let playing = nowPlaying, playing.canControl,
           let player = scriptablePlayers.first(where: { $0.scriptName == playing.appName }) {
            let action = switch command {
            case .togglePlayPause: "playpause"
            case .next: "next track"
            case .previous: "previous track"
            }
            run(script: "tell application \"\(player.scriptName)\" to \(action)",
                key: "cmd.\(player.scriptName).\(action)") { _ in }
        } else {
            // Для браузеров и прочих источников остаются системные медиа-клавиши:
            // их слушает то приложение, которое сейчас играет.
            MediaKeySender.send(command)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let playing = nowPlaying, playing.canControl,
              let player = scriptablePlayers.first(where: { $0.scriptName == playing.appName })
        else { return }

        run(script: "tell application \"\(player.scriptName)\" to set player position to \(Int(seconds))",
            key: "seek.\(player.scriptName)") { _ in }

        // Показываем новую позицию сразу, не дожидаясь ответа плеера.
        if var updated = nowPlaying {
            updated.elapsed = seconds
            updated.elapsedAt = .now
            nowPlaying = updated
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Опрос

    private func refresh() {
        if let started = refreshStartedAt {
            guard Date().timeIntervalSince(started) > refreshTimeout else { return }
        }

        let sources = AudioProcessMonitor.playingSources()
        guard !sources.isEmpty else {
            // Звук часто прерывается на доли секунды между треками — не убираем
            // плеер по первому же молчанию.
            silentPolls += 1
            if silentPolls >= 2 {
                lastFailureReason = "звук никто не воспроизводит"
                clearActivity()
            }
            return
        }
        silentPolls = 0

        // Если звучит плеер, которым мы умеем управлять, — берём его метаданные.
        // Он отвечает про себя сам и честно, слушать его незачем.
        if !settings.musicAccessBlocked,
           let player = scriptablePlayers.first(where: { player in
               sources.contains { $0.bundleID == player.bundleID }
                   && !deniedPlayers.contains(player.scriptName)
           }) {
            probe.stop()
            refreshStartedAt = Date()
            askPlayer(player, fallback: sources)
            return
        }

        guard let source = choose(from: sources) else {
            lastFailureReason = "поток вывода открыт, но звука в нём нет"
            clearActivity()
            return
        }
        present(source: source)
    }

    /// Кого показывать из тех, кто держит открытый поток вывода.
    ///
    /// Сначала по важности источника — плеер важнее браузера, браузер важнее
    /// мессенджера, — и только потом проверка, что кандидат правда звучит.
    /// Без проверки в вырезе висел Telegram, у которого поток открыт всё
    /// время, пока открыто окно.
    private func choose(
        from sources: [AudioProcessMonitor.Source]
    ) -> AudioProcessMonitor.Source? {
        let ranked = AudioProcessMonitor.ranked(sources).filter { !isKnownSilent($0) }
        guard let candidate = ranked.first else { return nil }

        // AirPlay слушать нечем: звук идёт мимо процесса-посредника.
        if candidate.isAirPlay { return candidate }

        // Пока тап открыт, macOS держит в строке меню свой значок записи.
        // Кому он мешает, тот выключает прослушивание целиком — и тогда мы
        // идём тем же путём, что и без разрешения: честно недосказываем.
        guard settings.listenToAudio else {
            probe.stop()
            return candidate.kind >= .browser ? candidate : nil
        }

        guard probe.isAvailable else {
            // Без разрешения на прослушивание тишину от звука не отличить.
            // Тогда лучше недосказать, чем соврать: обычные приложения
            // не показываем вовсе, остаются плееры и браузеры.
            return candidate.kind >= .browser ? candidate : nil
        }

        probe.listen(to: candidate.objectID)
        switch probe.isSilent {
        case .some(true):
            let strikes = (silentStrikes[candidate.pid] ?? 0) + 1
            silentStrikes[candidate.pid] = strikes
            guard strikes >= strikesToDrop else { return candidate }
            markSilent(candidate)
            return nil
        case .some(false):
            silentStrikes[candidate.pid] = 0
            return candidate
        case .none:
            // Вердикта ещё нет: у плеера и браузера звук — работа, их
            // показываем сразу, остальных дождёмся.
            return candidate.kind >= .browser ? candidate : nil
        }
    }

    private func isKnownSilent(_ source: AudioProcessMonitor.Source) -> Bool {
        guard let until = silentUntil[source.pid] else { return false }
        guard until > Date() else {
            silentUntil[source.pid] = nil
            return false
        }
        return true
    }

    private func markSilent(_ source: AudioProcessMonitor.Source) {
        silentUntil[source.pid] = Date().addingTimeInterval(10)
        silentStrikes[source.pid] = 0
        probe.stop()
    }

    private func askPlayer(_ player: ScriptablePlayer, fallback sources: [AudioProcessMonitor.Source]) {
        let artworkLine = player.hasArtworkURL
            ? " & \"\\n\" & (artwork url of current track)"
            : ""
        let identifierLine = player.hasIdentifier
            ? " & \"\\n\" & (id of current track)"
            : ""
        let script = """
        tell application "\(player.scriptName)"
            if player state is playing or player state is paused then
                return (name of current track) & "\\n" & (artist of current track) & "\\n" \
        & (duration of current track) & "\\n" & (player position) & "\\n" \
        & (player state is playing) & "\\n" & (album of current track)\(artworkLine)\(identifierLine)
            end if
        end tell
        """

        run(script: script, key: player.scriptName) { [weak self] outcome in
            guard let self else { return }
            self.refreshStartedAt = nil

            switch outcome {
            case .denied:
                self.deniedPlayers.insert(player.scriptName)
                self.settings.musicAccessBlocked = true
                self.accessDenied = true
                self.lastFailureReason = "\(player.scriptName): доступ запрещён"
                if let source = sources.first { self.present(source: source) }

            case .failed(let code):
                self.lastFailureReason = "\(player.scriptName): ошибка \(code)"
                if let source = sources.first { self.present(source: source) }

            case .success(let text):
                guard let response = MusicResponse.parse(text, durationDivisor: player.durationDivisor)
                else {
                    if let source = sources.first { self.present(source: source) }
                    return
                }
                self.accessDenied = false
                self.settings.musicAccessBlocked = false
                self.lastSuccess = Date()
                self.lastFailureReason = "—"
                self.present(response: response, player: player)
            }
        }
    }

    // MARK: - Показ

    private func present(response: MusicResponse, player: ScriptablePlayer) {
        let artwork = artwork(forURL: response.artworkURL, playerName: player.scriptName)
        let artist = enrichedArtist(for: response)

        publish(NowPlaying(
            title: response.title,
            subtitle: artist,
            appName: player.scriptName,
            album: response.album,
            artwork: artwork,
            fullArtwork: fullArtwork,
            blurredArtwork: blurredArtwork,
            duration: response.duration,
            elapsed: response.elapsed,
            elapsedAt: .now,
            isPlaying: response.isPlaying,
            accent: accentColor,
            canControl: true
        ))
    }

    /// Полный список исполнителей.
    ///
    /// У Spotify в AppleScript одно поле `artist`, и для трека с несколькими
    /// исполнителями оно называет только первого. Остальных добираем
    /// с публичной страницы трека — один запрос на трек, дальше из памяти.
    private func enrichedArtist(for response: MusicResponse) -> String? {
        guard settings.enrichSpotifyArtists,
              let known = response.artist, !known.isEmpty,
              let identifier = response.identifier,
              let id = SpotifyArtists.trackID(from: identifier)
        else { return response.artist }

        if let full = SpotifyArtists.cached(id) { return full }

        SpotifyArtists.lookup(id: id, known: known) { [weak self] full in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, var playing = self.nowPlaying,
                          playing.subtitle == known else { return }
                    playing.subtitle = full
                    self.publish(playing)
                }
            }
        }
        return known
    }

    /// Источник, который не умеет рассказать о себе: показываем приложение.
    /// Для трансляции с телефона названия трека нет — macOS его приложениям
    /// не отдаёт, — зато видно, что звук идёт, и полоски пляшут по-настоящему.
    private func present(source: AudioProcessMonitor.Source) {
        if source.isAirPlay {
            publish(NowPlaying(
                title: t("ui.5e1b8a30", "Звук с устройства"),
                subtitle: "AirPlay",
                appName: "AirPlay",
                artwork: nil,
                blurredArtwork: nil,
                duration: nil,
                elapsed: nil,
                isPlaying: true,
                accent: .cyan,
                canControl: false
            ))
            return
        }

        let icon = source.icon
        let title = browserTitle(for: source) ?? source.name

        publish(NowPlaying(
            title: title,
            subtitle: title == source.name ? nil : source.name,
            appName: source.name,
            artwork: icon,
            blurredArtwork: icon.flatMap { $0.blurred(radius: 24) },
            duration: nil,
            elapsed: nil,
            isPlaying: true,
            accent: icon?.accentColor ?? .pink,
            canControl: false
        ))
    }

    /// Заголовок вкладки браузера — из кэша, обновление в фоне.
    ///
    /// Раньше AppleScript выполнялся прямо здесь, на главном потоке: браузер,
    /// задумавшийся на тяжёлом сайте, подвешивал весь интерфейс вместе с собой.
    private func browserTitle(for source: AudioProcessMonitor.Source) -> String? {
        guard source.kind == .browser, let bundleID = source.bundleID else { return nil }

        let cached = browserTitles[bundleID]
        if let cached, Date().timeIntervalSince(cached.at) < 3 { return cached.title }

        let appName = source.name
        Task { [weak self, runner] in
            let title = await BrowserTitleReader.activeTabTitle(bundleID: bundleID, runner: runner)
            await MainActor.run {
                guard let self, let title else { return }
                self.browserTitles[bundleID] = (title, Date())
                // Заголовок пришёл уже после того, как карточка показана —
                // обновляем её на месте, не дожидаясь следующего опроса.
                if self.nowPlaying?.appName == appName { self.refresh() }
            }
        }
        return cached?.title
    }

    private func publish(_ playing: NowPlaying) {
        let changed = playing.differsMeaningfully(from: nowPlaying)
        nowPlaying = playing
        writeSnapshot(playing, artworkChanged: changed)

        if settings.showLyrics, playing.canControl {
            lyrics.load(
                title: playing.title,
                artist: playing.subtitle,
                duration: playing.duration
            )
        }

        guard changed else { return }
        center.upsert(
            Activity(
                id: activityID,
                title: playing.title,
                subtitle: playing.subtitle ?? playing.appName,
                symbol: playing.appName == "AirPlay"
                    ? "airplayaudio"
                    : (playing.isPlaying ? "waveform" : "pause.fill"),
                tint: playing.accent,
                artwork: playing.artwork,
                priority: .ambient,
                indicator: playing.isPlaying ? .audioBars : .none
            )
        )
    }

    private func clearActivity() {
        guard nowPlaying != nil else { return }
        nowPlaying = nil
        center.remove(id: activityID)
        lyrics.clear()
        try? FileManager.default.removeItem(at: NowPlayingSnapshot.fileURL)
    }

    /// Строка, звучащая сейчас: заставка живёт в отдельном процессе и в сеть
    /// за текстами не ходит, поэтому получает готовую строку в снимке.
    private func lyricLines(
        for playing: NowPlaying
    ) -> (previous: String?, current: String?, next: String?) {
        guard settings.showLyrics else { return (nil, nil, nil) }
        return lyrics.triple(at: playing.elapsedNow() ?? 0)
    }

    /// Очередь для снимка заставки. Заставка читает файл в своём процессе,
    /// и опоздание на полсекунды ей безразлично — а вот главному потоку
    /// не безразлично кодирование PNG и запись на диск.
    private static let snapshotQueue = DispatchQueue(
        label: "dev.kekch.aura.snapshot", qos: .utility
    )

    /// Снимок для заставки: она работает в отдельном процессе и читает файл.
    ///
    /// Раньше это делалось прямо в `publish`, на главном потоке. За одну
    /// смену трека `publish` случается трижды — ответ плеера, пришедшая
    /// обложка, дополненный список исполнителей, — и каждый раз это была
    /// запись JSON, а при смене обложки ещё и кодирование PNG. Отсюда
    /// подтормаживание ровно в момент переключения песни.
    private func writeSnapshot(_ playing: NowPlaying, artworkChanged: Bool) {
        // Всё, что нужно фоновой записи, снимается здесь, на главном потоке:
        // дальше уезжают только значения.
        let lyrics = lyricLines(for: playing)
        let accent = NSColor(playing.accent).usingColorSpace(.sRGB)?.hexString ?? "#FF2D55"
        // Заставка занимает весь экран — ей нужен исходник.
        let artwork = artworkChanged ? (playing.fullArtwork ?? playing.artwork) : nil
        let previousPath = lastArtworkPath

        Self.snapshotQueue.async {
            let artworkPath = artworkChanged
                ? NowPlayingSnapshot.writeArtwork(artwork)
                : previousPath

            NowPlayingSnapshot(
                title: playing.title,
                subtitle: playing.subtitle,
                appName: playing.appName,
                isPlaying: playing.isPlaying,
                duration: playing.duration,
                elapsed: playing.elapsed,
                elapsedAt: playing.elapsedAt,
                accentHex: accent,
                artworkPath: artworkPath,
                lyricPrevious: lyrics.previous,
                lyric: lyrics.current,
                lyricNext: lyrics.next,
                updatedAt: Date()
            ).write()

            if artworkChanged {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.lastArtworkPath = artworkPath }
                }
            }
        }
    }

    // MARK: - Обложка

    private func artwork(forURL urlString: String?, playerName: String) -> NSImage? {
        guard let urlString, !urlString.isEmpty else { return artworkCache?.image }
        if let cached = artworkCache, cached.key == urlString { return cached.image }
        guard let url = URL(string: urlString) else { return artworkCache?.image }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let original = NSImage(data: data) else { return }
            let side: CGFloat = 220
            let image = NSImage(size: CGSize(width: side, height: side))
            image.lockFocus()
            original.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            image.unlockFocus()

            // Оригинал в память не кладём. Apple Music отдаёт обложки
            // до 3000×3000 — это 36 МБ в разобранном виде на каждый трек,
            // а крупнее 640 её нигде не рисуют: витрина показывает 320.
            let full = Self.bounded(original, maxSide: 640)

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.artworkCache = (urlString, image)
                    self.fullArtwork = full
                    self.accentColor = image.accentColor
                    // Размываем сразу и держим готовую копию: во время
                    // анимации острова считать это уже поздно.
                    self.blurredArtwork = image.blurred(radius: 26)

                    // Ставим обложку прямо в текущую карточку. Раньше здесь
                    // запускался новый опрос — ещё один круг AppleScript,
                    // то есть лишние доли секунды со старой картинкой.
                    guard var updated = self.nowPlaying else { return }
                    updated.artwork = image
                    updated.blurredArtwork = self.blurredArtwork
                    updated.accent = self.accentColor
                    self.publish(updated)
                }
            }
        }.resume()

        return artworkCache?.image
    }

    /// Копия обложки не крупнее заданной стороны. Меньшую отдаёт как есть:
    /// перерисовывать её незачем, а качество от этого только теряется.
    nonisolated static func bounded(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return image }

        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let copy = NSImage(size: target)
        copy.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: target))
        copy.unlockFocus()
        return copy
    }

    private func run(
        script source: String,
        key: String,
        completion: @escaping (ScriptOutcome) -> Void
    ) {
        Task { [runner] in
            let outcome = await runner.run(source: source, key: key)
            await MainActor.run {
                switch outcome {
                case .success(let text): completion(.success(text))
                case .denied: completion(.denied)
                case .failed(let code): completion(.failed(code))
                }
            }
        }
    }
}
