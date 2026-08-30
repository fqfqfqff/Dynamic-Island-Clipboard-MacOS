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
    /// Когда приложение запустилось — чтобы в диагностике было видно,
    /// за какое время память успела вырасти.
    private let started = Date()
    private let notificationHistory = NotificationHistoryWindow()
    private lazy var countdown = TimerProvider(center: activities)

    private lazy var screenshots = ScreenshotActivityProvider(center: activities, clipboard: clipboard, settings: settings)
    private lazy var notifications = NotificationMirrorProvider(center: activities, settings: settings)
    private lazy var focus = FocusActivityProvider(center: activities)
    private lazy var calendar = CalendarActivityProvider(center: activities)
    private lazy var network = NetworkActivityProvider(center: activities)
    private lazy var downloads = DownloadActivityProvider(center: activities)
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
    private let audioOutput = AudioOutputWatcher()
    private let updates = UpdateChecker()
    private var providerSubscriptions = Set<AnyCancellable>()
    private lazy var control = ControlServer { [weak self] command in
        self?.handle(command) ?? #"{"ok":false,"error":"приложение не готово"}"#
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Считаем запуски, которые не дожили до конца: три подряд — и
        // источники выключаются, чтобы приложение хотя бы открылось.
        SafeMode.beginLaunch()
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
        NotificationCenter.default.addObserver(
            self, selector: #selector(showQuickMenu), name: .auraQuickMenu, object: nil
        )

        notchController = NotchWindowController(
            activities: activities,
            media: media,
            settings: settings,
            spectrum: spectrum,
            lyrics: lyrics,
            shelf: shelf,
            notifications: notifications
        )
        notchController?.attachToScreenWithNotch()

        // Пришло уведомление — вырез вырастает карточкой. Значок с числом
        // непрочитанных ставит сам провайдер и держит до прочтения.
        notifications.onMessage = { [weak self] message in
            guard let self, self.settings.notificationStyle == "card" else { return }
            // Код подтверждения держим дольше: его читают и набирают руками,
            // и пяти секунд на это не хватает.
            let hold = self.settings.notificationHold + (message.code == nil ? 0 : 4)
            self.notchController?.presentEvent(hold: hold)
        }

        // Выдернули наушники — музыка замолкает, а не переезжает в динамики.
        audioOutput.onHeadphonesRemoved = { [weak self] in
            guard let self, self.settings.pauseOnHeadphonesRemoved else { return }
            guard self.media.nowPlaying?.isPlaying == true else { return }
            self.media.send(.togglePlayPause)
        }
        audioOutput.start()

        // Универсальный буфер: скопировали на телефоне — на Маке об этом
        // не сообщает ничто, содержимое просто молча лежит и ждёт.
        clipboard.onRemoteContent = { [weak self] item in
            self?.activities.upsert(
                Activity(
                    id: "clipboard.remote",
                    title: t("ui.d92a1c04", "с другого устройства"),
                    subtitle: item.title,
                    symbol: "iphone",
                    tint: .blue,
                    priority: .normal,
                    indicator: .none,
                    expiresAt: Date().addingTimeInterval(10)
                )
            )
        }

        clipboard.start()
        activities.start()
        battery.start()
        control.start()
        setUpPowerSaving()
        applyProviderSettings()
        observeProviderSettings()
        applyPausedState()
        setUpIdleShowcase()
        updates.start()

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
        network.stop()
        downloads.stop()
        control.stop()
        spectrum.stop()
        screenState.stop()
        audioOutput.stop()
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

        case .bannerShot:
            let area = CGRect(x: 900, y: 0, width: 810, height: 260)
            BannerIconReader.shot(of: area) { url in
                AppDelegate.log("снимок баннера: \(url?.path ?? "не вышел")")
            }
            return ok(["снимок": "пишется в Application Support/Aura/banner-shot.png"])

        case .screenShot:
            let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1710, height: 1112)
            BannerIconReader.shot(of: CGRect(origin: .zero, size: screen.size)) { url in
                AppDelegate.log("снимок экрана: \(url?.path ?? "не вышел")")
            }
            return ok(["снимок": "Application Support/Aura/banner-shot.png"])

        case .openSettings:
            showSettings()
            return ok()

        case .openHistory:
            notificationHistory.show()
            return ok()

        case .timer(let minutes):
            if let minutes, minutes > 0 {
                countdown.start(minutes: minutes)
                return ok(["осталось": TimerProvider.spelled(countdown.remaining)])
            }
            countdown.stop()
            return ok(["таймер": "остановлен"])

        case .openNotification:
            guard let app = notifications.latest?.app else {
                return ok(["уведомление": "нет"])
            }
            notifications.open(app: app)
            notchController?.close()
            return ok(["открываю": app])

        case .clearNotifications:
            notifications.markAllRead()
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
            payload["зеркалоСлушает"] = notifications.isWatching
            payload["ключиЗаписей"] = notifications.storeKeys
            payload["колонкиБазы"] = notifications.storeColumns
            payload["гдеИконки"] = IconHunt.look()
            payload["базаУведомлений"] = notifications.readsStore
            payload["режимФокусирования"] = focus.activeMode
            payload["строкаМенюСистемы"] = RecordingIndicator.labels()
            payload["снимки"] = screenshots.diagnostics
            // Разговоры видно поимённо: разбиение по чатам иначе не проверить —
            // снаружи виден только общий счётчик активностей.
            payload["записьЭкрана"] = notifications.canReadIconsFromScreen
            payload["последниеБаннеры"] = notifications.recentBanners.suffix(4).map { $0 }
            payload["чаты"] = notifications.threads.reduce(into: [String: Int]()) {
                $0[$1.key.replacingOccurrences(of: "\u{1}", with: " → ")] = $1.value
            }
            // Расход памяти виден сразу: он растёт медленно и незаметно —
            // за ночь с витриной приложение раздувалось с 80 МБ до 286.
            payload["памятьМБ"] = Diagnostics.footprintMB
            payload["живётМинут"] = Int(Date().timeIntervalSince(started) / 60)
            // Иконка приложения — самое хрупкое место в разборе баннера:
            // если приложение не опознано, не будет ни значка, ни цвета,
            // ни снятия по прочтении. Поэтому её видно в диагностике.
            payload["последнееУведомление"] = notifications.latest.map { message in
                [
                    "приложение": message.app,
                    "значокНайден": message.icon != nil,
                    "значокСвой": NotificationMirrorProvider.isMonogram(message.icon),
                    "значокСЭкрана": notifications.lastIconFromScreen,
                    "идентификатор": message.bundleID ?? "—",
                    "тип": String(describing: message.kind),
                ] as [String: Any]
            } ?? ["—": true]
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

        add(to: menu, title: t("ui.c40d9e17", "История буфера"), key: "⌥⌘V", action: #selector(showClipboard))
        add(to: menu, title: t("ui.b21f7530", "Витрина плеера"), key: "⌥⌘M", action: #selector(toggleShowcase))
        add(to: menu, title: t("ui.e6b21f04", "Настройки…"), key: "", action: #selector(showSettings))
        add(to: menu, title: t("ui.9d3c04b8", "Разрешения и настройка"), key: "", action: #selector(showOnboarding))
        menu.addItem(.separator())

        // Пункт появляется только в аварийном режиме — иначе он лишний,
        // а в нём это единственный способ вернуть источники, не открывая
        // терминал.
        if SafeMode.isActive {
            add(
                to: menu,
                title: t("ui.6a30fe17", "Аварийный режим: включить источники"),
                key: "",
                action: #selector(leaveSafeMode)
            )
            menu.addItem(.separator())
        }

        add(
            to: menu,
            title: t("ui.71e5a2c0", "Показывать вырез"),
            key: "",
            action: #selector(toggleNotchVisible),
            checked: settings.showNotch
        )
        add(
            to: menu,
            title: t("ui.30b94f16", "Приостановить Aura"),
            key: "",
            action: #selector(togglePaused),
            checked: settings.paused
        )
        menu.addItem(.separator())

        add(to: menu, title: t("ui.4a8e01d5", "Запросить доступ к плееру"), key: "", action: #selector(requestMusicAccess))
        menu.addItem(timerItem())
        add(to: menu, title: t("ui.5f1a90e3", "История уведомлений"), key: "", action: #selector(showNotificationHistory))
        add(to: menu, title: t("ui.e520c81a", "Очистить историю буфера"), key: "", action: #selector(clearClipboard))
        menu.addItem(.separator())
        if let release = updates.available {
            add(
                to: menu,
                title: String(format: t("ui.9e3b17a0", "Есть версия %@"), release.version),
                key: "",
                action: #selector(openRelease)
            )
            menu.addItem(.separator())
        }
        add(to: menu, title: t("ui.2a2a0c98", "Выйти из Aura"), key: "", action: #selector(quit))

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
        alert.addButton(withTitle: t("ui.f127f2a1", "Понятно"))
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

    /// Пункт «Таймер» с готовыми временами. Пока таймер идёт, первым
    /// пунктом стоит остановка и видно, сколько осталось.
    private func timerItem() -> NSMenuItem {
        let item = NSMenuItem(title: t("ui.a70f2d31", "Таймер"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        if countdown.isRunning {
            let stop = NSMenuItem(
                title: String(
                    format: t("ui.36c8b0a1", "Остановить — осталось %@"),
                    TimerProvider.spelled(countdown.remaining)
                ),
                action: #selector(stopTimer),
                keyEquivalent: ""
            )
            stop.target = self
            submenu.addItem(stop)
            submenu.addItem(.separator())
        }

        for minutes in [1, 3, 5, 10, 15, 25, 45, 60] {
            let entry = NSMenuItem(
                title: String(format: t("ui.d1e4703b", "%d мин"), minutes),
                action: #selector(startTimer(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.tag = minutes
            submenu.addItem(entry)
        }

        item.submenu = submenu
        return item
    }

    @objc private func startTimer(_ sender: NSMenuItem) {
        countdown.start(minutes: Double(sender.tag))
    }

    @objc private func stopTimer() {
        countdown.stop()
    }

    @objc private func showNotificationHistory() {
        notificationHistory.show()
    }

    @objc private func leaveSafeMode() {
        SafeMode.reset()
        applyProviderSettings()
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
            notifications.stop()
            focus.stop()
            calendar.stop()
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

    @objc private func openRelease() {
        guard let release = updates.available else { return }
        NSWorkspace.shared.open(release.url)
    }

    /// Быстрое меню под курсором: то, за чем чаще всего лезут в строку
    /// состояния, — не выходя из выреза.
    @objc private func showQuickMenu() {
        let menu = NSMenu()

        if media.nowPlaying != nil {
            let playing = media.nowPlaying?.isPlaying == true
            menu.addItem(
                withTitle: playing ? t("ui.5a0e73c1", "Пауза") : t("ui.c904e1b7", "Играть"),
                action: #selector(togglePlayback),
                keyEquivalent: ""
            ).target = self
            menu.addItem(.separator())
        }

        menu.addItem(
            withTitle: t("ui.b7f30c25", "Спрятать остров"),
            action: #selector(hideIsland),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: t("ui.e6b21f04", "Настройки…"),
            action: #selector(showSettings),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: t("ui.2a2a0c98", "Выйти из Aura"),
            action: #selector(quit),
            keyEquivalent: ""
        ).target = self

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func togglePlayback() {
        media.send(.togglePlayPause)
    }

    @objc private func hideIsland() {
        settings.showNotch = false
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
            && settings.listenToAudio
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
    /// Зеркало уведомлений должно знать про режим фокусирования: при нём
    /// карточка не показывается.
    private func connectFocusToNotifications() {
        notifications.isFocusOn = { [weak self] in
            guard let self else { return false }
            return self.focus.activeMode != "выключен"
        }
    }

    private func applyProviderSettings() {
        connectFocusToNotifications()
        // Аварийный режим: приложение падало при запуске три раза подряд.
        // Источники — единственное, что лезет в систему, поэтому они
        // и выключаются; окно настроек и меню остаются доступны.
        guard !SafeMode.isActive else {
            media.stop()
            screenshots.stop()
            battery.stop()
            notifications.stop()
            focus.stop()
            calendar.stop()
            network.stop()
            downloads.stop()
            NSLog("Aura: аварийный режим — источники выключены после %d падений",
                  SafeMode.failedLaunches)
            return
        }

        settings.enableMusic ? media.start() : media.stop()
        settings.enableScreenshots ? screenshots.start() : screenshots.stop()
        if settings.enableBattery { battery.start() } else { battery.stop() }
        if settings.enableNotifications { notifications.start() } else { notifications.stop() }
        if settings.enableFocus { focus.start() } else { focus.stop() }
        if settings.enableCalendar { calendar.start() } else { calendar.stop() }
        if settings.enableNetwork { network.start() } else { network.stop() }
        if settings.enableDownloads { downloads.start() } else { downloads.stop() }
    }

    private func observeProviderSettings() {
        // dropFirst у каждого источника отдельно: @Published отдаёт текущее
        // значение сразу при подписке, и без этого настройки применялись бы
        // лишний раз на старте.
        let changes: [AnyPublisher<Void, Never>] = [
            settings.$enableMusic.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableScreenshots.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableBattery.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableNotifications.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableFocus.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableCalendar.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableNetwork.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$enableDownloads.dropFirst().map { _ in () }.eraseToAnyPublisher(),
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
