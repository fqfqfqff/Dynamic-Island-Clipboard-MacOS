import AppKit
import Combine

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    public override init() { super.init() }

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var notchController: NotchWindowController?
    private let settings = SettingsStore()
    private lazy var clipboard = ClipboardService(settings: settings)
    private let activities = ActivityCenter()
    private lazy var battery = BatteryActivityProvider(center: activities)
    private let lyrics = LyricsProvider()
    private let shelf = ShelfService()
    private lazy var media = NowPlayingProvider(
        center: activities,
        settings: settings,
        lyrics: lyrics
    )
    private lazy var volume = VolumeActivityProvider(center: activities)
    private lazy var screenshots = ScreenshotActivityProvider(center: activities, clipboard: clipboard)
    private lazy var bluetooth = BluetoothActivityProvider(center: activities)
    private lazy var notifications = NotificationMirrorProvider(center: activities)
    private lazy var focus = FocusActivityProvider(center: activities)
    private lazy var calendar = CalendarActivityProvider(center: activities)
    private lazy var clipboardWindow = ClipboardWindowController(
        clipboard: clipboard,
        settings: settings
    )
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private lazy var onboarding = OnboardingWindowController(
        settings: settings,
        media: media,
        spectrum: spectrum
    )
    private lazy var showcase = ShowcaseWindowController(media: media, lyrics: lyrics, settings: settings)
    private let idle = IdleWatcher()
    private let spectrum = AudioSpectrumMonitor()
    private let screenState = ScreenStateWatcher()
    private var providerSubscriptions = Set<AnyCancellable>()
    private lazy var control = ControlServer { [weak self] command in
        self?.handle(command) ?? #"{"ok":false,"error":"приложение не готово"}"#
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(showSettings), name: .auraOpenSettings, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(quit), name: .auraQuit, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(showOnboarding), name: .auraShowOnboarding, object: nil
        )

        notchController = NotchWindowController(
            activities: activities,
            media: media,
            settings: settings,
            spectrum: spectrum,
            lyrics: lyrics,
            shelf: shelf
        )
        notchController?.attachToScreenWithNotch()

        clipboard.start()
        activities.start()
        battery.start()
        control.start()
        setUpPowerSaving()
        applyProviderSettings()
        observeProviderSettings()
        applyPausedState()
        setUpIdleShowcase()

        // Первый запуск: без объяснения, что за разрешения и зачем,
        // приложение выглядит наполовину сломанным.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.onboarding.showIfNeeded()
        }

        HotkeyManager.shared.register(.clipboardHistory) { [weak self] in
            self?.clipboardWindow.toggle()
        }

        HotkeyManager.shared.register(.showcase) { [weak self] in
            self?.showcase.toggle()
        }

        // Вырез живёт на конкретном экране: при смене конфигурации мониторов
        // (закрыли крышку, подключили внешний) окно нужно пересадить.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    public func applicationWillTerminate(_ notification: Notification) {
        clipboard.stop()
        activities.stop()
        battery.stop()
        media.stop()
        screenshots.stop()
        control.stop()
        spectrum.stop()
        screenState.stop()
        NotificationCenter.default.removeObserver(self)
    }

    /// Внешние команды приходят двумя путями — через сокет и через `aura://`,
    /// но обрабатываются одним кодом.
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = try? ControlCommand.parse(url: url) else { continue }
            _ = handle(command)
        }
    }

    private func handle(_ command: ControlCommand) -> String {
        switch command {
        case .push(let payload):
            activities.upsert(payload.makeActivity())
            return ok()

        case .remove(let id):
            activities.remove(id: "external.\(id)")
            return ok()

        case .list:
            let list = activities.activities.map { activity -> [String: Any] in
                [
                    "id": activity.id,
                    "title": activity.title,
                    "subtitle": activity.subtitle ?? "",
                    "priority": activity.priority.rawValue,
                ]
            }
            return ok(["activities": list])

        case .open:
            notchController?.open()
            return ok()

        case .close:
            notchController?.close()
            return ok()

        case .showcase(let open):
            open ? showcase.show() : showcase.hide()
            return ok()

        case .autostart(let enabled):
            let changed = LaunchAtLogin.set(enabled)
            return ok(["автозапуск": LaunchAtLogin.isEnabled, "изменено": changed])

        case .status:
            var payload: [String: Any] = notchController?.diagnostics ?? [:]
            payload["активностей"] = activities.activities.count
            payload["элементовВБуфере"] = clipboard.items.count
            payload["музыка"] = media.nowPlaying?.title ?? "нет"
            payload["правоВставки"] = Paster.canPaste
            payload["плеер"] = media.diagnostics
            payload["уведомления"] = notifications.isAvailable
            payload["фокус"] = focus.isAvailable
            payload["спектр"] = [
                "работает": spectrum.isRunning,
                "уровни": spectrum.levels.map { Int($0 * 100) },
            ]
            payload["автовставка"] = settings.autoPaste
            return ok(payload)

        case .ping:
            let version = Bundle.main
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
            return ok(["app": "Aura", "version": version])
        }
    }

    private func ok(_ extra: [String: Any] = [:]) -> String {
        var payload: [String: Any] = ["ok": true]
        payload.merge(extra) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"ok":true}"#
        }
        return text
    }

    @objc private func screensChanged() {
        notchController?.attachToScreenWithNotch()
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "Aura"
        )
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    /// Левый клик — история буфера, правый или с Control — меню.
    ///
    /// Тип события проверяется по всем вариантам: система шлёт то `rightMouseUp`,
    /// то `rightMouseDown`, и попытка угадать один из них оставляла меню
    /// недоступным вовсе.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent

        // Правую кнопку определяем тремя способами сразу: тип события приходит
        // то Up, то Down, а иногда система вообще не отдаёт currentEvent.
        let isRight = event?.type == .rightMouseUp
            || event?.type == .rightMouseDown
            || event?.modifierFlags.contains(.control) == true

        Self.log("клик по иконке: тип=\(event.map { "\($0.type.rawValue)" } ?? "нет события") "
                 + "кнопка=\(event?.buttonNumber ?? -1) нажато=\(NSEvent.pressedMouseButtons) "
                 + "правый=\(isRight)")

        if isRight {
            showMenu()
        } else {
            clipboardWindow.toggle()
        }
    }

    /// Пишет в ~/Library/Application Support/Aura/debug.log. Нужен потому, что
    /// у фонового приложения без окна иначе негде увидеть, что происходит.
    static func log(_ message: String) {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aura/debug.log")
        let line = "\(Date().formatted(date: .omitted, time: .standard))  \(message)\n"

        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// Меню строится заново на каждый показ: у половины пунктов есть галочки,
    /// и статичное меню показывало бы устаревшее состояние.
    ///
    /// Показываем его штатным для строки состояния способом — через `menu`
    /// самого элемента. Ручной `popUp` рисовал меню мимо иконки, не подсвечивал
    /// её и закрывался от события отпускания кнопки, прилетавшего следом.
    private func showMenu() {
        guard let statusItem, let button = statusItem.button else { return }

        let menu = NSMenu()
        menu.delegate = self

        add(to: menu, title: "История буфера", key: "⌥⌘V", action: #selector(showClipboard))
        add(to: menu, title: "Витрина плеера", key: "⌥⌘M", action: #selector(toggleShowcase))
        add(to: menu, title: "Настройки…", key: "", action: #selector(showSettings))
        add(to: menu, title: "Разрешения и настройка", key: "", action: #selector(showOnboarding))
        menu.addItem(.separator())

        add(
            to: menu,
            title: "Показывать вырез",
            key: "",
            action: #selector(toggleNotchVisible),
            checked: settings.showNotch
        )
        add(
            to: menu,
            title: "Приостановить Aura",
            key: "",
            action: #selector(togglePaused),
            checked: settings.paused
        )
        menu.addItem(.separator())

        add(to: menu, title: "Запросить доступ к плееру", key: "", action: #selector(requestMusicAccess))
        add(to: menu, title: "Очистить историю буфера", key: "", action: #selector(clearClipboard))
        menu.addItem(.separator())
        add(to: menu, title: "Выйти из Aura", key: "", action: #selector(quit))

        statusItem.menu = menu
        button.performClick(nil)
    }

    /// Меню снимается сразу после закрытия: пока оно висит на элементе, левый
    /// клик открывал бы его вместо истории буфера.
    public func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }

    private func add(
        to menu: NSMenu,
        title: String,
        key: String,
        action: Selector,
        checked: Bool = false
    ) {
        let item = NSMenuItem(
            title: key.isEmpty ? title : "\(title)   \(key)",
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        item.state = checked ? .on : .off
        menu.addItem(item)
    }

    /// В разделе «Автоматизация» нет кнопки «добавить»: строка про Aura
    /// появляется там только после того, как мы сами попробуем обратиться
    /// к плееру и система спросит разрешение. Этот пункт вызывает попытку.
    @objc private func requestMusicAccess() {
        settings.musicAccessBlocked = false
        media.retryAccess()

        let alert = NSAlert()
        alert.messageText = "Запрос отправлен"
        alert.informativeText = pgrepPlayers().isEmpty
            ? "Сначала запустите Spotify или Музыку и включите трек, затем повторите — без работающего плеера системе нечего спрашивать."
            : "Если появится окно «Aura хочет управлять…», нажмите «OK». После этого Aura появится в разделе «Автоматизация»."
        alert.addButton(withTitle: "Понятно")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func pgrepPlayers() -> [String] {
        let ids = ["com.spotify.client", "com.apple.Music"]
        return NSWorkspace.shared.runningApplications
            .compactMap(\.bundleIdentifier)
            .filter(ids.contains)
    }

    @objc private func toggleNotchVisible() {
        settings.showNotch.toggle()
        notchController?.setVisible(settings.showNotch && !settings.paused)
    }

    @objc private func togglePaused() {
        settings.paused.toggle()
        applyPausedState()
    }

    /// Пауза выключает всё разом: и вырез, и слежение за источниками.
    private func applyPausedState() {
        notchController?.setVisible(settings.showNotch && !settings.paused)
        updateSpectrum()
        if settings.paused {
            media.stop()
            screenshots.stop()
            bluetooth.stop()
            notifications.stop()
            focus.stop()
            calendar.stop()
            volume.stop()
            battery.stop()
            clipboard.stop()
        } else {
            clipboard.start()
            applyProviderSettings()
        }
    }

    @objc private func showClipboard() {
        clipboardWindow.toggle()
    }

    @objc private func toggleShowcase() {
        showcase.toggle()
    }

    @objc private func showOnboarding() {
        onboarding.show()
    }

    @objc private func showSettings() {
        settingsWindow.show()
    }

    /// Анализ звука — самая дорогая часть приложения, поэтому он включается
    /// только когда действительно нужен: что-то играет, экран не спит,
    /// приложение не на паузе. В остальное время тап закрыт и не стоит ничего.
    private func setUpPowerSaving() {
        screenState.onChange = { [weak self] _ in self?.updateSpectrum() }
        screenState.start()

        media.$nowPlaying
            .map { $0?.isPlaying == true }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateSpectrum() }
            .store(in: &providerSubscriptions)

        settings.$reactToAudio
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateSpectrum() }
            .store(in: &providerSubscriptions)

        updateSpectrum()
    }

    private func updateSpectrum() {
        let shouldRun = settings.reactToAudio
            && !settings.paused
            && screenState.isVisible
            && media.nowPlaying?.isPlaying == true

        shouldRun ? spectrum.start() : spectrum.stop()
    }

    /// Витрина «вместо экрана блокировки»: пока пользователь отошёл, экран
    /// показывает плеер с часами. Рисовать на самом экране блокировки macOS
    /// сторонним приложениям не даёт — там скрывается вся сессия пользователя.
    private func setUpIdleShowcase() {
        idle.onIdle = { [weak self] in
            guard let self, self.settings.showcaseOnIdle else { return }
            guard self.media.nowPlaying != nil else { return }
            self.showcase.show()
        }
        idle.onActive = { [weak self] in
            guard let self, self.settings.showcaseOnIdle else { return }
            self.showcase.hide()
        }

        settings.$showcaseIdleMinutes
            .receive(on: RunLoop.main)
            .sink { [weak self] minutes in self?.idle.threshold = max(60, minutes * 60) }
            .store(in: &providerSubscriptions)

        settings.$showcaseOnIdle
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                enabled ? self?.idle.start() : self?.idle.stop()
            }
            .store(in: &providerSubscriptions)
    }

    /// Источники включаются и выключаются на лету, без перезапуска.
    private func applyProviderSettings() {
        settings.enableMusic ? media.start() : media.stop()
        settings.enableScreenshots ? screenshots.start() : screenshots.stop()
        if settings.enableVolume { volume.start() } else { volume.stop() }
        if settings.enableBattery { battery.start() } else { battery.stop() }
        if settings.enableBluetooth { bluetooth.start() } else { bluetooth.stop() }
        if settings.enableNotifications { notifications.start() } else { notifications.stop() }
        if settings.enableFocus { focus.start() } else { focus.stop() }
        if settings.enableCalendar { calendar.start() } else { calendar.stop() }
    }

    private func observeProviderSettings() {
        // dropFirst у каждого источника отдельно: @Published отдаёт текущее
        // значение сразу при подписке, и без этого настройки применялись бы
        // лишний раз на старте.
        let changes: [AnyPublisher<Void, Never>] = [
            settings.$enableMusic.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableVolume.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableScreenshots.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableBattery.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableBluetooth.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableNotifications.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableFocus.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableCalendar.dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.applyProviderSettings() }
            .store(in: &providerSubscriptions)
    }

    @objc private func toggleNotch() {
        notchController?.toggle()
    }

    @objc private func clearClipboard() {
        clipboard.clear()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
