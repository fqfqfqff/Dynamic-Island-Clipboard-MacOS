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
        var artwork: NSImage?
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
    }

    private enum ScriptOutcome {
        case success(String)
        case denied
        case failed(Int)
    }

    private let scriptablePlayers = [
        ScriptablePlayer(bundleID: "com.spotify.client", scriptName: "Spotify",
                         durationDivisor: 1000, hasArtworkURL: true),
        ScriptablePlayer(bundleID: "com.apple.Music", scriptName: "Music",
                         durationDivisor: 1, hasArtworkURL: false),
    ]

    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var accessDenied = false

    private let center: ActivityCenter
    private let settings: SettingsStore
    private let lyrics: LyricsProvider
    private let activityID = "media.nowplaying"

    private var ticker: Timer?
    private var deniedPlayers: Set<String> = []
    private var compiledScripts: [String: NSAppleScript] = [:]
    private var refreshStartedAt: Date?
    private let refreshTimeout: TimeInterval = 15
    private var artworkCache: (key: String, image: NSImage)?
    private var accentColor: Color = .pink
    private var blurredArtwork: NSImage?
    private var lastArtworkPath: String?
    private var silentPolls = 0
    private var lastSuccess: Date?
    private var lastFailureReason = "опроса ещё не было"

    init(center: ActivityCenter, settings: SettingsStore, lyrics: LyricsProvider) {
        self.center = center
        self.settings = settings
        self.lyrics = lyrics
    }

    var diagnostics: [String: Any] {
        [
            "источникиЗвука": AudioProcessMonitor.playingSources().map(\.name),
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
            start()
        }
    }

    func start() {
        stop()
        let interval: TimeInterval = isDetailed ? 1.5 : (settings.showLyrics ? 2 : 4)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        refresh()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        center.remove(id: activityID)
        nowPlaying = nil
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
        if !settings.musicAccessBlocked,
           let player = scriptablePlayers.first(where: { player in
               sources.contains { $0.bundleID == player.bundleID }
                   && !deniedPlayers.contains(player.scriptName)
           }) {
            refreshStartedAt = Date()
            askPlayer(player, fallback: sources)
            return
        }

        present(source: AudioProcessMonitor.preferred(from: sources) ?? sources[0])
    }

    private func askPlayer(_ player: ScriptablePlayer, fallback sources: [AudioProcessMonitor.Source]) {
        let artworkLine = player.hasArtworkURL
            ? " & \"\\n\" & (artwork url of current track)"
            : ""
        let script = """
        tell application "\(player.scriptName)"
            if player state is playing or player state is paused then
                return (name of current track) & "\\n" & (artist of current track) & "\\n" \
        & (duration of current track) & "\\n" & (player position) & "\\n" \
        & (player state is playing)\(artworkLine)
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

        publish(NowPlaying(
            title: response.title,
            subtitle: response.artist,
            appName: player.scriptName,
            artwork: artwork,
            blurredArtwork: blurredArtwork,
            duration: response.duration,
            elapsed: response.elapsed,
            elapsedAt: .now,
            isPlaying: response.isPlaying,
            accent: accentColor,
            canControl: true
        ))
    }

    /// Источник, который не умеет рассказать о себе: показываем приложение.
    /// Для трансляции с телефона названия трека нет — macOS его приложениям
    /// не отдаёт, — зато видно, что звук идёт, и полоски пляшут по-настоящему.
    private func present(source: AudioProcessMonitor.Source) {
        if source.isAirPlay {
            publish(NowPlaying(
                title: "Звук с устройства",
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
        let title = BrowserTitleReader.isBrowser(source.bundleID)
            ? (BrowserTitleReader.activeTabTitle(bundleID: source.bundleID) ?? source.name)
            : source.name

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

    /// Снимок для заставки: она работает в отдельном процессе и читает файл.
    private func writeSnapshot(_ playing: NowPlaying, artworkChanged: Bool) {
        var artworkPath = lastArtworkPath
        if artworkChanged {
            artworkPath = NowPlayingSnapshot.writeArtwork(playing.artwork)
            lastArtworkPath = artworkPath
        }

        NowPlayingSnapshot(
            title: playing.title,
            subtitle: playing.subtitle,
            appName: playing.appName,
            isPlaying: playing.isPlaying,
            duration: playing.duration,
            elapsed: playing.elapsed,
            elapsedAt: playing.elapsedAt,
            accentHex: NSColor(playing.accent).usingColorSpace(.sRGB)?.hexString ?? "#FF2D55",
            artworkPath: artworkPath,
            lyricPrevious: lyricLines(for: playing).previous,
            lyric: lyricLines(for: playing).current,
            lyricNext: lyricLines(for: playing).next,
            updatedAt: Date()
        ).write()
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

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.artworkCache = (urlString, image)
                    self.accentColor = image.accentColor
                    // Размываем сразу и держим готовую копию: во время
                    // анимации острова считать это уже поздно.
                    self.blurredArtwork = image.blurred(radius: 26)
                    self.refresh()
                }
            }
        }.resume()

        return artworkCache?.image
    }

    private func run(
        script source: String,
        key: String,
        completion: @escaping (ScriptOutcome) -> Void
    ) {
        let cached = compiledScripts[key]
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let script = cached ?? NSAppleScript(source: source)
            var error: NSDictionary?
            let output = script?.executeAndReturnError(&error)

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let script, cached == nil { self.compiledScripts[key] = script }

                    if let error {
                        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                        completion(code == -1743 ? .denied : .failed(code))
                    } else {
                        completion(.success(output?.stringValue ?? ""))
                    }
                }
            }
        }
    }
}
