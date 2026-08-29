import AppKit
import ApplicationServices
import SwiftUI

/// Показывает в вырезе уведомления других приложений.
///
/// Единого API для чтения чужих уведомлений в macOS нет. База Центра
/// уведомлений закрыта TCC и требует полного доступа к диску, поэтому здесь
/// выбран второй путь: наблюдение за окнами баннеров через Accessibility —
/// то же разрешение, которое уже нужно для вставки из буфера.
///
/// Системный баннер при этом никуда не девается: мы его дублируем, а не
/// заменяем — спрятать чужое окно приложение не может.
///
/// Показ устроен в два слоя, как на iPhone:
/// - карточка события: вырез вырастает сверху вниз, видно от кого и что;
/// - значок в компактном виде: иконка приложения слева, число непрочитанных
///   справа — держится, пока пользователь не откроет само приложение.
@MainActor
final class NotificationMirrorProvider: ObservableObject {

    /// Что пришло. Тип сообщения виден из текста баннера: мессенджеры пишут
    /// в него «Голосовое сообщение» вместо самого сообщения.
    struct Message: Equatable, Identifiable {
        enum Kind: Equatable {
            case text
            case voice
            /// Кружок — видеосообщение.
            case videoMessage
            case photo
            case video
            case sticker
            case file
            case call

            /// Значок типа: он показывается рядом с текстом.
            var symbol: String {
                switch self {
                case .text: "message.fill"
                case .voice: "waveform.circle.fill"
                case .videoMessage: "circle.circle.fill"
                case .photo: "photo.fill"
                case .video: "play.rectangle.fill"
                case .sticker: "face.smiling.inverse"
                case .file: "doc.fill"
                case .call: "phone.fill"
                }
            }

            /// Чем заменить текст, когда сам текст показывать нельзя или
            /// его и не было.
            var wording: String {
                switch self {
                case .text: t("ui.4a1b7c20", "Сообщение")
                case .voice: t("ui.b3d61e84", "Голосовое сообщение")
                case .videoMessage: t("ui.c7f20a93", "Видеосообщение")
                case .photo: t("ui.1d8e35b7", "Фотография")
                case .video: t("ui.e04c9182", "Видео")
                case .sticker: t("ui.62a7d4f1", "Стикер")
                case .file: t("ui.90b5e2c6", "Файл")
                case .call: t("ui.af38016d", "Звонок")
                }
            }
        }

        let id: UUID
        var app: String
        /// Идентификатор приложения. Имя из баннера и `localizedName`
        /// совпадают не всегда, а снимать непрочитанное нужно наверняка.
        var bundleID: String?
        var sender: String
        var body: String?
        var kind: Kind
        /// Код подтверждения из текста, если он там есть.
        var code: String?
        var icon: NSImage?
        var tint: Color
        var receivedAt: Date

        static func == (lhs: Message, rhs: Message) -> Bool { lhs.id == rhs.id }
    }

    /// Последнее пришедшее — его и показывает карточка события.
    @Published private(set) var latest: Message?
    /// Сколько непрочитанного накопилось по каждому приложению.
    @Published private(set) var unread: [String: Int] = [:]
    /// Сколько непрочитанного в каждом разговоре: «приложение|собеседник».
    ///
    /// Пять сообщений от пятерых — это пять разных дел, а не «5» на значке
    /// мессенджера. В раскрытой панели у каждого своя строка, и прочитать
    /// можно по одному.
    @Published private(set) var threads: [String: Int] = [:]

    /// Пришло новое уведомление — острову пора вырасти.
    var onMessage: ((Message) -> Void)?

    private let center: ActivityCenter
    private let settings: SettingsStore
    private var observer: AXObserver?
    private var element: AXUIElement?
    /// Что уже показывали и когда. Со сроком: одно и то же сообщение
    /// в одном разговоре повторяется, и через минуту это уже новое событие,
    /// а не тот же баннер, прочитанный второй раз.
    private var seen: [String: Date] = [:]
    /// Включён ли сейчас режим фокусирования. Ставится снаружи: состояние
    /// читает провайдер фокуса, у него для этого есть доступ к файлу.
    var isFocusOn: () -> Bool = { false }
    /// База Центра уведомлений — то, что пришло без баннера.
    private let store = NotificationStore()
    /// Значки, снятые с самих баннеров: для приложений, которых на Маке нет.
    private let bannerIcons = BannerIconReader()
    /// Разрешена ли запись экрана — без неё значки с телефона не снять.
    var canReadIconsFromScreen: Bool { bannerIcons.isAllowed }
    /// Последний снятый значок пришёл с экрана, а не из системы.
    private(set) var lastIconFromScreen = false
    /// Последние разобранные баннеры — для диагностики.
    ///
    /// Уведомления с телефона приходят не в том же виде, что от приложений
    /// на Маке, и понять, почему у одного из них не нашлось значка, можно
    /// только по узлам самого баннера.
    private(set) var recentBanners: [[String]] = []
    /// Обход открытых баннеров. Работает, только пока они на экране.
    private var sweepTimer: Timer?
    /// Медленный обход-страховка. Работает всё время, пока зеркало включено.
    private var idleSweepTimer: Timer?
    private var sweepStartedAt = Date()
    /// Окно последнего баннера — через него работает ответ.
    private var latestBanner: AXUIElement?
    /// Имя приложения из баннера → его идентификатор.
    private var bundleIDs: [String: String] = [:]
    /// Когда в приложении последний раз появлялось непрочитанное.
    private var firstUnreadAt: [String: Date] = [:]
    /// Таймер гашения. Заводится, только когда есть что гасить.
    private var expiryTimer: Timer?

    private let bannerHost = "com.apple.notificationcenterui"

    init(center: ActivityCenter, settings: SettingsStore) {
        self.center = center
        self.settings = settings
    }

    var isAvailable: Bool { AXIsProcessTrusted() }

    /// Слушаем ли мы баннеры прямо сейчас. Отличается от `isAvailable`:
    /// разрешение может быть выдано, а наблюдатель не заведён — например,
    /// если центра уведомлений не было в списке процессов при запуске.
    var isWatching: Bool { observer != nil }

    /// Читаем ли мы базу Центра уведомлений — запасной источник для того,
    /// что система не показала баннером.
    var readsStore: Bool { store.isAvailable }

    /// Подставить уведомление вручную — для снимков интерфейса и тестов.
    func inject(_ message: Message?) {
        latest = message
    }

    func injectUnread(app: String, count: Int, sender: String? = nil) {
        unread[app] = count
        if let sender {
            threads[Self.threadKey(app: app, sender: sender)] = count
        }
    }

    func start() {
        stop()
        guard AXIsProcessTrusted() else {
            NSLog("Aura: зеркало уведомлений не запущено — нет доступа к Универсальному доступу")
            return
        }
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: bannerHost
        ).first else { return }

        let pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        self.element = element

        var observer: AXObserver?
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard AXObserverCreate(pid, { _, element, _, context in
            guard let context else { return }
            let provider = Unmanaged<NotificationMirrorProvider>
                .fromOpaque(context).takeUnretainedValue()
            // Колбэк приходит на главном потоке рун-лупа, где наблюдатель и создан.
            MainActor.assumeIsolated { provider.handleBanner(element) }
        }, &observer) == .success, let observer else { return }

        // Список установленных приложений собирается заранее и в фоне:
        // на главном потоке он стоил бы секунды заминки на первом же
        // уведомлении.
        Self.warmUp { [weak self] in self?.refreshIcons() }

        let added = AXObserverAddNotification(
            observer, element, kAXWindowCreatedNotification as CFString, context
        )
        if added != .success {
            AppDelegate.log("зеркало уведомлений: подписка не удалась, код \(added.rawValue)")
        }

        // `commonModes`, а не `defaultMode`: пока открыто меню или идёт
        // прокрутка, рун-луп сидит в режиме слежения — и в нём события
        // Универсального доступа до нас не доходили вовсе.
        for mode in [CFRunLoopMode.defaultMode, .commonModes] {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), mode)
        }
        self.observer = observer

        // Медленный обход работает всегда, а не только после события
        // «создано окно». Событие приходит не на каждый баннер, а если
        // подписка отвалилась — то и вовсе ни на один. Обход раз в полторы
        // секунды стоит одной проверки списка окон и гарантирует, что
        // баннер не пропустим.
        startIdleSweep()

        // И запасной источник: то, что система не показала баннером.
        store.watch { [weak self] records in
            guard let self else { return }
            for record in records { self.present(record: record) }
        }

        // Открыл приложение — значит, прочитал. Другого способа узнать это
        // у нас нет: чужие уведомления система помечать прочитанными не даёт.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationFocusChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        // И ушёл из него — тоже значит, прочитал.
        //
        // Без этого половина уведомлений не снималась никогда: сообщение
        // приходит, когда человек уже сидит в Telegram, события «переключились
        // на Telegram» больше не будет — оно и так впереди, — и значок висел
        // вечно. Уход из приложения закрывает ровно этот случай.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationFocusChanged(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )
    }

    func stop() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observer = nil
        element = nil
        latestBanner = nil
        stopSweep()
        store.stop()
        idleSweepTimer?.invalidate()
        idleSweepTimer = nil
        seen.removeAll()

        NSWorkspace.shared.notificationCenter.removeObserver(self)
        markAllRead()
    }

    // MARK: - Прочитано

    @objc private func applicationFocusChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication else { return }

        // Сверяем по идентификатору, а если его нет — по имени без учёта
        // регистра. Имя из баннера и `localizedName` расходятся чаще, чем
        // кажется: у баннера оно берётся из своей локализации.
        let name = unread.keys.first { candidate in
            if let bundleID = bundleIDs[candidate], bundleID == app.bundleIdentifier {
                return true
            }
            return candidate.caseInsensitiveCompare(app.localizedName ?? "") == .orderedSame
        }
        guard let name else { return }
        markRead(app: name)
    }

    /// Убирает значок приложения из выреза.
    func markRead(app: String) {
        guard unread[app] != nil || threads.keys.contains(where: { Self.app(ofThread: $0) == app })
        else { return }

        unread[app] = nil
        bundleIDs[app] = nil
        firstUnreadAt[app] = nil
        for thread in threads.keys where Self.app(ofThread: thread) == app {
            threads[thread] = nil
            center.remove(id: Self.activityID(forThread: thread))
        }
        if latest?.app == app { latest = nil }
    }

    /// Гасит значки, которые провисели дольше отведённого.
    ///
    /// Уведомление, на которое не отреагировали за десять минут, — уже не
    /// новость. Держать его вечно значит превратить остров в свалку, из
    /// которой значки убирают руками.
    private func scheduleExpiry() {
        guard settings.notificationBadgeTTL > 0 else { return }
        guard expiryTimer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireOld() }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    private func expireOld() {
        let ttl = settings.notificationBadgeTTL * 60
        if ttl > 0 {
            let now = Date()
            for (app, since) in firstUnreadAt where now.timeIntervalSince(since) >= ttl {
                markRead(app: app)
            }
        }

        // Гасить больше нечего — таймеру тоже незачем работать.
        if firstUnreadAt.isEmpty {
            expiryTimer?.invalidate()
            expiryTimer = nil
        }
    }

    /// Снимает непрочитанное с приложения, в котором человек сидит.
    ///
    /// Событие «переключились на приложение» приходит только при переключении.
    /// Если сообщение пришло в Telegram, который и так впереди, значок не снял
    /// бы никто — он висел бы до перезапуска. Поэтому спустя несколько секунд
    /// смотрим ещё раз: приложение всё ещё впереди — значит, прочитали.
    ///
    /// Задержка нужна, чтобы значок успели увидеть: проверяют уведомления,
    /// отправляя сообщение себе.
    private func clearIfFrontmost() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      let front = NSWorkspace.shared.frontmostApplication else { return }

                let name = self.unread.keys.first { candidate in
                    if let bundleID = self.bundleIDs[candidate],
                       bundleID == front.bundleIdentifier { return true }
                    return candidate.caseInsensitiveCompare(front.localizedName ?? "")
                        == .orderedSame
                }
                guard let name else { return }
                self.markRead(app: name)
            }
        }
    }

    /// Прочитан один разговор, а не всё приложение: остальные чаты остаются.
    func markThreadRead(_ thread: String) {
        guard let count = threads[thread] else { return }
        threads[thread] = nil
        center.remove(id: Self.activityID(forThread: thread))

        let app = Self.app(ofThread: thread)
        let left = max(0, (unread[app] ?? count) - count)
        if left == 0 {
            unread[app] = nil
            bundleIDs[app] = nil
            firstUnreadAt[app] = nil
            if latest?.app == app { latest = nil }
        } else {
            unread[app] = left
        }
    }

    /// Имя приложения по идентификатору активности — по нему строка
    /// в раскрытой панели умеет пометить себя прочитанной.
    static func appName(fromActivityID id: String) -> String? {
        let prefix = "notification."
        guard id.hasPrefix(prefix) else { return nil }
        return app(ofThread: String(id.dropFirst(prefix.count)))
    }

    /// Разговор по идентификатору активности — чтобы строка в панели умела
    /// пометить прочитанным именно свой чат.
    static func thread(fromActivityID id: String) -> String? {
        let prefix = "notification."
        guard id.hasPrefix(prefix) else { return nil }
        return String(id.dropFirst(prefix.count))
    }

    func markAllRead() {
        for thread in threads.keys { center.remove(id: Self.activityID(forThread: thread)) }
        threads.removeAll()
        unread.removeAll()
        bundleIDs.removeAll()
        firstUnreadAt.removeAll()
        expiryTimer?.invalidate()
        expiryTimer = nil
        latest = nil
    }

    // MARK: - Ключи

    /// Разделитель, которого не бывает в именах приложений и людей.
    private static let separator = "\u{1}"

    static func threadKey(app: String, sender: String) -> String {
        "\(app)\(separator)\(sender)"
    }

    static func app(ofThread thread: String) -> String {
        thread.components(separatedBy: separator).first ?? thread
    }

    static func sender(ofThread thread: String) -> String {
        let parts = thread.components(separatedBy: separator)
        return parts.count > 1 ? parts[1] : ""
    }

    private static func activityID(forThread thread: String) -> String {
        "notification.\(thread)"
    }

    // MARK: - Разбор баннера

    /// Можно ли ответить прямо сейчас.
    ///
    /// Отвечает не Aura: мы нажимаем кнопку «Ответить» на системном баннере,
    /// и поле ввода открывает он же. Это всё, что доступно снаружи — своего
    /// API для ответа на чужое уведомление в macOS нет.
    ///
    /// Поэтому и живёт эта возможность ровно столько, сколько висит баннер:
    /// исчез он — отвечать больше нечему.
    var canReply: Bool { replyButton() != nil }

    /// Открыть приложение, которое прислало уведомление.
    ///
    /// «Ответить» живёт, только пока на экране висит системный баннер, —
    /// то есть считанные секунды, а при «Не беспокоить» не бывает вовсе.
    /// Открыть приложение можно всегда: идентификатор мы знаем и из базы,
    /// и из самого баннера.
    func open(app: String) {
        let bundleID = bundleIDs[app]
            ?? Self.application(named: app)?.bundleIdentifier

        let url = bundleID.flatMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        } ?? Self.installedApplicationURL(named: app)

        guard let url else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        markRead(app: app)
    }

    /// Путь установленного приложения по имени — для случая, когда
    /// идентификатора нет.
    static func installedApplicationURL(named name: String) -> URL? {
        installedApplication(named: name)
    }

    /// Нажать «Ответить» на баннере. Дальше человек печатает в него сам.
    func reply() {
        guard let button = replyButton() else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    private func replyButton() -> AXUIElement? {
        guard let latestBanner else { return nil }
        return Self.button(in: latestBanner, titled: Self.replyTitles)
    }

    private static let replyTitles: Set<String> = [
        "ответить", "reply", "ответ",
    ]

    /// Ищет кнопку с подходящим названием. Баннер перерисовывается системой,
    /// и держать ссылку на саму кнопку нельзя — она протухает вместе с ним.
    private static func button(
        in element: AXUIElement,
        titled titles: Set<String>,
        depth: Int = 0
    ) -> AXUIElement? {
        guard depth < 8 else { return nil }

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if role as? String == kAXButtonRole {
            for key in [kAXTitleAttribute, kAXDescriptionAttribute] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
                   let text = (value as? String)?.lowercased(),
                   titles.contains(where: { text == $0 || text.hasPrefix($0) }) {
                    return element
                }
            }
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return nil }

        for child in list {
            if let found = button(in: child, titled: titles, depth: depth + 1) { return found }
        }
        return nil
    }

    private func handleBanner(_ window: AXUIElement) {
        latestBanner = window
        // Баннер дорисовывается не мгновенно: сразу после создания окна
        // текстов внутри ещё нет.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let texts = Self.texts(in: window)
            self.remember(texts)
            if let content = Self.content(from: texts) { self.present(content) }
            self.startSweep()
        }
    }

    /// Значок доехал позже самого уведомления — подставляем его и в карточку,
    /// и в строки списка: карточка живёт несколько секунд, а значок в списке
    /// остаётся до прочтения.
    private func apply(icon: NSImage, app: String) {
        lastIconFromScreen = true

        if var message = latest, message.app == app {
            message.icon = icon
            if settings.notificationTintFromIcon { message.tint = icon.accentColor }
            latest = message
        }

        for (thread, count) in threads where Self.app(ofThread: thread) == app {
            center.updateArtwork(id: Self.activityID(forThread: thread), artwork: icon)
            _ = count
        }
    }

    /// Перебрать значки заново — например, когда список установленных
    /// приложений наконец собрался.
    private func refreshIcons() {
        for thread in threads.keys {
            let app = Self.app(ofThread: thread)
            guard let icon = Self.icon(named: app), !Self.isMonogram(icon) else { continue }
            center.updateArtwork(id: Self.activityID(forThread: thread), artwork: icon)
        }

        if var message = latest, Self.isMonogram(message.icon),
           let icon = Self.icon(named: message.app), !Self.isMonogram(icon) {
            message.icon = icon
            latest = message
        }
    }

    private func remember(_ texts: [String]) {
        guard !texts.isEmpty, recentBanners.last != texts else { return }
        recentBanners.append(texts)
        if recentBanners.count > 10 { recentBanners.removeFirst() }
    }

    /// Сколько времени одно и то же сообщение считается тем же самым.
    ///
    /// Обход перечитывает баннер каждые полсекунды, поэтому без отсева остров
    /// дёргался бы без конца. Но срок нужен: «ок» от того же человека через
    /// минуту — это новое сообщение, а не тот же баннер.
    nonisolated static let repeatWindow: TimeInterval = 45

    nonisolated static func isRepeat(
        shownAt: Date?, now: Date, within: TimeInterval = repeatWindow
    ) -> Bool {
        guard let shownAt else { return false }
        return now.timeIntervalSince(shownAt) < within
    }

    // MARK: - Запасной источник: база Центра уведомлений

    /// Уведомление, которого не было в баннере.
    ///
    /// Баннеров может не быть вовсе: при «Не беспокоить» система их не
    /// показывает, а в настройках macOS их можно выключить у любого
    /// приложения. Уведомление при этом приходит — просто молча. База знает
    /// о нём всё равно, и знает лучше баннера: там есть идентификатор
    /// приложения, а значит, точная иконка, а не поиск по имени.
    /// Каким правилом показывать уведомление с учётом режима фокусирования.
    ///
    /// Фокус включают, чтобы не отвлекаться, и система при нём молчит. Лезть
    /// поверх неё карточкой — ровно то, от чего человек и прятался. Значок
    /// остаётся: он не отвлекает, а посмотреть можно самому.
    nonisolated static func rule(_ rule: String, focusOn: Bool, respectFocus: Bool) -> String {
        guard rule == "card", focusOn, respectFocus else { return rule }
        return "badge"
    }

    /// Сколько ждать баннера, прежде чем показывать то же самое из базы.
    ///
    /// Одно уведомление приходит обоими путями, и тексты у них расходятся:
    /// баннер отдаёт три строки как есть, база — заголовок, подзаголовок
    /// и текст по отдельности. Отсев по содержимому такие пары не ловит,
    /// и карточка показывалась дважды, второй раз продлевая себе жизнь.
    /// Поэтому у базы своя проверка — по разговору, а не по тексту.
    private static let bannerGrace: TimeInterval = 12
    /// Когда разговор последний раз показывали.
    private var shownThreads: [String: Date] = [:]

    private func present(record: NotificationStore.Record) {
        let appName = Self.applicationName(forBundleID: record.bundleID) ?? record.title

        // Заголовок у мессенджеров — это отправитель, а у остальных — само
        // приложение. Если заголовок совпал с именем приложения, отправителя
        // берём из подзаголовка.
        let sender = record.title == appName ? (record.subtitle ?? appName) : record.title
        let body = [record.title == appName ? nil : record.subtitle, record.body]
            .compactMap { $0 }
            .joined(separator: " · ")

        let thread = Self.threadKey(app: appName, sender: sender)
        if let shown = shownThreads[thread],
           Date().timeIntervalSince(shown) < Self.bannerGrace {
            // Это уже показал баннер — он же и подробнее.
            return
        }

        present(
            Content(app: appName, sender: sender, body: body.isEmpty ? nil : body),
            bundleID: record.bundleID
        )
    }

    /// Имя приложения по идентификатору — точнее любого поиска по названию.
    static func applicationName(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }

        // Имя берём на языке системы — тем же, каким приложение называет
        // себя в баннере. Иначе одно уведомление приходит двумя путями под
        // разными именами: «Редактор скриптов» из баннера и «Script Editor»
        // из базы, — и в острове оказывается два разговора вместо одного.
        let language = Locale.preferredLanguages.first?
            .components(separatedBy: "-").first ?? "en"

        return systemLanguageName(of: url, language: language)
            ?? FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
    }

    /// Иконка по идентификатору приложения — без поиска по имени вовсе.
    static func icon(forBundleID bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Обход открытых баннеров

    /// Событие «создано окно» приходит не на каждое уведомление.
    ///
    /// Пока баннер на экране, следующее сообщение система показывает в том же
    /// окне — просто меняет в нём текст. Нового окна нет, события нет, и всё,
    /// что пришло следом, мы теряли: остров не вырастал, превью не было.
    /// Ровно так и терялась половина уведомлений.
    ///
    /// Поэтому, пока баннеры на экране, их содержимое перечитывается. Работа
    /// живёт секунды: не осталось баннеров — обход останавливается сам.
    /// Постоянный медленный обход — страховка на случай, когда события нет.
    private func startIdleSweep() {
        idleSweepTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweepBanners(idle: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleSweepTimer = timer
    }

    private func startSweep() {
        sweepStartedAt = Date()
        guard sweepTimer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweepBanners() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
    }

    private func stopSweep() {
        sweepTimer?.invalidate()
        sweepTimer = nil
    }

    private func sweepBanners(idle: Bool = false) {
        // Частый обход дольше полуминуты не живёт: медленный всё равно
        // продолжит следить.
        if !idle, Date().timeIntervalSince(sweepStartedAt) >= 30 { return stopSweep() }

        guard let element else {
            if !idle { stopSweep() }
            return
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXWindowsAttribute as CFString, &value
        ) == .success, let windows = value as? [AXUIElement], !windows.isEmpty else {
            if !idle { stopSweep() }
            return
        }

        for window in windows {
            let texts = Self.texts(in: window)
            // Раскрытый центр уведомлений — это не баннер: в нём висят
            // виджеты, погода и биржа, и разбирать его как сообщение нельзя.
            guard texts.count <= 12 else { continue }
            remember(texts)
            guard let content = Self.content(from: texts) else { continue }
            latestBanner = window
            present(content)
        }
    }

    private func present(_ content: Content, bundleID knownBundle: String? = nil) {
        // Один и тот же баннер система пересоздаёт, а обход читает его
        // каждые полсекунды заново — без отсева остров дёргался бы без конца.
        let key = "\(content.app)|\(content.sender)|\(content.body ?? "")"
        let now = Date()
        if Self.isRepeat(shownAt: seen[key], now: now) { return }
        seen[key] = now
        if seen.count > 60 {
            for (old, when) in seen where now.timeIntervalSince(when) > 120 { seen[old] = nil }
        }

        settings.rememberNotificationApp(content.app)
        var rule = settings.notificationRule(for: content.app)
        guard rule != "off" else { return }

        // Режим фокусирования включают, чтобы не отвлекаться. Система при
        // нём молчит, и лезть поверх неё карточкой — ровно то, от чего
        // человек и прятался. Значок остаётся: он не отвлекает.
        rule = Self.rule(rule, focusOn: isFocusOn(), respectFocus: settings.respectFocus)

        let application = Self.application(named: content.app)
        // Имя приложения в баннере бывает пустым — уведомления с телефона
        // приходят не в том же виде, что от приложений на Маке. Тогда буква
        // берётся от отправителя: он есть всегда, и это лучше пустого места.
        // Идентификатор приложения — самый точный путь к иконке: искать
        // по имени тогда не нужно вовсе.
        var icon = knownBundle.flatMap { Self.icon(forBundleID: $0) }
            ?? Self.icon(named: content.app)
            ?? Self.monogram(for: content.sender)

        // Иконки нет ни среди запущенных, ни среди установленных — значит,
        // приложение живёт на телефоне. Там, где её взять неоткуда, берём
        // с самого баннера: система рисует её сама.
        let ownIcon = Self.isMonogram(icon) ? bannerIcons.cached(for: content.app) : nil
        if let ownIcon { icon = ownIcon }
        lastIconFromScreen = ownIcon != nil
        let kind = Self.kind(from: content.body)
        let tint = settings.notificationTintFromIcon
            ? (icon?.accentColor ?? .indigo)
            : .indigo

        let message = Message(
            id: UUID(),
            app: content.app,
            bundleID: application?.bundleIdentifier,
            sender: content.sender,
            body: settings.notificationShowBody ? content.body : nil,
            kind: kind,
            code: content.body.flatMap(ClipboardItem.code(in:)),
            icon: icon,
            tint: tint,
            receivedAt: Date()
        )

        latest = message

        // Своей иконки не нашлось — приложение живёт на телефоне. Снимаем
        // её с баннера, пока он ещё на экране, и подставляем, когда придёт.
        // Скрытый ключ для проверки самой съёмки на приложении, у которого
        // иконка и так есть: `defaults write dev.kekch.aura forceBannerIcon -bool true`.
        // Без него путь включается только там, где иконки действительно нет.
        let forced = UserDefaults.standard.bool(forKey: "forceBannerIcon")
        if Self.isMonogram(icon) || forced, settings.readIconsFromBanner {
            let frame = latestBanner.flatMap { Self.iconFrame(in: $0) }
            AppDelegate.log("значок с баннера: кадр \(frame.map(String.init(describing:)) ?? "не найден")")

            if let frame {
                bannerIcons.read(app: content.app, iconFrame: frame) { [weak self] image in
                    self?.apply(icon: image, app: content.app)
                }
            }
        }

        // Уведомление от приложения, которое сейчас впереди, человек уже
        // прочитал — он в него и смотрит. Значок в таком случае не нужен:
        // события «переключились на приложение» больше не будет, оно и так
        // активно, и значок повис бы навсегда.
        //
        // Но проверяют работу уведомлений, отправляя сообщение себе — и тогда
        // значок не появляется вовсе, что выглядит как потеря. Поэтому
        // поведение вынесено в настройку.
        if application?.isActive == true, !settings.notificationBadgeWhenAppOpen {
            if rule == "card" { onMessage?(message) }
            return
        }

        NotificationArchive.append(
            app: content.app,
            sender: content.sender,
            body: content.body,
            bundleID: knownBundle ?? application?.bundleIdentifier
        )
        shownThreads[Self.threadKey(app: content.app, sender: content.sender)] = Date()
        if shownThreads.count > 40 {
            let cutoff = Date().addingTimeInterval(-Self.bannerGrace * 4)
            shownThreads = shownThreads.filter { $0.value > cutoff }
        }
        unread[content.app, default: 0] += 1
        bundleIDs[content.app] = knownBundle ?? application?.bundleIdentifier

        let thread = Self.threadKey(app: content.app, sender: content.sender)
        threads[thread, default: 0] += 1
        if firstUnreadAt[content.app] == nil { firstUnreadAt[content.app] = Date() }
        scheduleExpiry()

        // Человек мог уже прочитать всё в самом приложении: он в нём и сидит,
        // а событие «переключились на приложение» больше не придёт — оно
        // и так впереди. Без этой проверки значок висел бы до перезапуска.
        clearIfFrontmost()

        // Значок в компактном виде: иконка слева, счётчик справа. Живёт,
        // пока пользователь не откроет приложение.
        center.upsert(
            Activity(
                id: Self.activityID(forThread: thread),
                title: message.sender,
                subtitle: message.body ?? kind.wording,
                symbol: kind.symbol,
                // Счётчик непрочитанных — белый. Цвет приложения работает
                // на обводке карточки, а в компактном виде рядом с самой
                // иконкой он только спорит с ней.
                tint: .white,
                artwork: icon,
                priority: .important,
                // Единицу не рисуем: одно сообщение — это и так одно
                // сообщение, а цифра рядом с текстом только отвлекает.
                indicator: (threads[thread] ?? 1) > 1
                    ? .text("\(threads[thread] ?? 1)")
                    : .none
            )
        )

        if rule == "card" { onMessage?(message) }
    }

    struct Content: Equatable {
        var app: String
        /// Кто написал: у мессенджеров во второй строке баннера имя.
        var sender: String
        var body: String?
    }

    /// Разбирает окно баннера на приложение, отправителя и текст.
    ///
    /// Устроено оно не так, как кажется. Живой баннер отдаёт вот что:
    ///
    /// ```
    /// ["Notification Center",                            ← заголовок окна
    ///  "Телеграм, Никита, рабочий чат, привет",          ← сводка целиком
    ///  "Никита", "рабочий чат", "привет"]                ← содержимое
    /// ```
    ///
    /// Имя приложения есть только в сводке, первым элементом до запятой, —
    /// в отдельном узле его нет вовсе. Раньше за приложение принимался
    /// заголовок окна, то есть буквально «Notification Center»: отсюда
    /// и отсутствие иконки, и запасной цвет, и то, что уведомление никогда
    /// не считалось прочитанным — сверять было не с чем.
    nonisolated static func content(from texts: [String]) -> Content? {
        // Заголовок окна и кнопки — такие же текстовые узлы.
        let noise: Set<String> = [
            "Notification Center", "Центр уведомлений",
            "Закрыть", "Close", "Параметры", "Options", "Ответить", "Reply",
            "Показать", "Show", "Отклонить", "Dismiss",
        ]
        var cleaned = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !noise.contains($0) }

        guard !cleaned.isEmpty else { return nil }

        // Стопка — это не одно уведомление, а несколько, свёрнутых системой
        // в один баннер. Разобрать её нельзя: тексты всех сообщений идут
        // подряд, и в карточку попадала каша из чужих обрывков. Пропускаем:
        // база Центра уведомлений отдаст их по одному и чисто.
        guard !isStack(cleaned) else { return nil }

        let summary = cleaned.removeFirst()
        let app = summary
            .components(separatedBy: ", ")
            .first?
            .trimmingCharacters(in: .whitespaces) ?? summary

        guard !cleaned.isEmpty else { return nil }
        let sender = cleaned.removeFirst()

        return Content(
            app: app,
            sender: sender,
            body: cleaned.isEmpty ? nil : cleaned.joined(separator: " · ")
        )
    }

    /// Свёрнуты ли в баннер несколько уведомлений сразу.
    ///
    /// Система подписывает такой баннер словом «стопкой» и складывает
    /// в него тексты всех сообщений подряд.
    nonisolated static func isStack(_ texts: [String]) -> Bool {
        let markers = ["стопкой", "стопка", "stacked", "stack of"]
        if texts.contains(where: { text in
            let lower = text.lowercased()
            return markers.contains { lower.contains($0) }
        }) { return true }

        // Обычный баннер — это имя, отправитель и текст: пять-шесть узлов
        // с кнопками. Больше бывает только у стопки.
        return texts.count > 6
    }

    /// Что именно прислали. Мессенджеры не пишут в баннер вложение — они
    /// пишут его название словами, и по нему тип узнаётся однозначно.
    nonisolated static func kind(from body: String?) -> Message.Kind {
        guard let body = body?.lowercased(), !body.isEmpty else { return .text }

        let markers: [(Message.Kind, [String])] = [
            (.videoMessage, ["видеосообщение", "video message", "кружок"]),
            (.voice, ["голосовое сообщение", "voice message", "аудиосообщение", "audio message"]),
            (.call, ["входящий звонок", "incoming call", "звонок", "calling"]),
            (.photo, ["фотография", "фото", "photo", "image"]),
            (.video, ["видео", "video"]),
            (.sticker, ["стикер", "sticker", "gif", "анимация"]),
            (.file, ["файл", "документ", "file", "document"]),
        ]

        for (kind, words) in markers where words.contains(where: { body.contains($0) }) {
            // Слово должно быть всем содержимым баннера, а не частью фразы:
            // «посмотри это видео» — обычный текст, а не видео.
            let trimmed = body.trimmingCharacters(in: .punctuationCharacters)
            if words.contains(where: { trimmed == $0 || trimmed.hasPrefix($0) }) {
                return kind
            }
        }
        return .text
    }

    /// Собирает все текстовые узлы окна баннера.
    /// Где в баннере нарисован значок приложения.
    ///
    /// Элемента-картинки в баннере нет вовсе: Универсальный доступ отдаёт
    /// только группу баннера и три строки текста. Зато по ним место значка
    /// вычисляется однозначно — он занимает всё поле слева от текста:
    ///
    ///     AXGroup     [1350,55 344×73]   ← баннер
    ///       AXStaticText [1408,67 …]     ← от кого
    ///       AXStaticText [1408,83 …]     ← чат
    ///       AXStaticText [1408,99 …]     ← сообщение
    ///
    /// Отступ до текста — 58 точек, значок внутри него квадратный и по центру
    /// по вертикали. Считаем от настоящих координат, а не от зашитых чисел:
    /// вёрстка баннера меняется от версии к версии.
    static func iconFrame(in window: AXUIElement) -> CGRect? {
        guard let banner = bannerGroup(in: window) else { return nil }
        let gap = banner.textLeft - banner.frame.minX
        guard gap > 24, gap < banner.frame.width / 2 else { return nil }

        // Поле слева от текста — это отступ, значок и ещё отступ. Значок
        // занимает примерно две трети поля.
        let side = min(gap * 0.66, banner.frame.height * 0.62)
        return CGRect(
            x: banner.frame.minX + (gap - side) / 2,
            y: banner.frame.midY - side / 2,
            width: side,
            height: side
        )
    }

    /// Группа баннера и левый край её текста.
    private static func bannerGroup(
        in element: AXUIElement, depth: Int = 0
    ) -> (frame: CGRect, textLeft: CGFloat)? {
        guard depth < 8 else { return nil }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &children
        ) == .success, let list = children as? [AXUIElement] else { return nil }

        // Сначала вглубь: нужна самая узкая группа, в которой лежат тексты,
        // а не окно целиком.
        for child in list {
            if let found = bannerGroup(in: child, depth: depth + 1) { return found }
        }

        let texts = list.compactMap { child -> CGRect? in
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                child, kAXRoleAttribute as CFString, &role
            ) == .success, (role as? String) == kAXStaticTextRole else { return nil }
            return frame(of: child)
        }

        guard texts.count >= 2, let own = frame(of: element), own.width > 60 else { return nil }
        guard let textLeft = texts.map(\.minX).min() else { return nil }
        return (own, textLeft)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXPositionAttribute as CFString, &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            element, kAXSizeAttribute as CFString, &sizeValue
        ) == .success else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let positionValue, let sizeValue,
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        return CGRect(origin: origin, size: size)
    }

    /// Больше этого числа узлов у баннера не бывает: три строки, кнопки
    /// и заголовок окна. Раскрытый центр уведомлений — это сотни узлов,
    /// и обходить их целиком дважды в секунду незачем: как только стало
    /// ясно, что это не баннер, обход прекращается.
    private static let textLimit = 14

    private static func texts(in element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < 8 else { return [] }
        var result: [String] = []

        for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
               let text = value as? String, !text.isEmpty {
                result.append(text)
                break
            }
        }

        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let list = children as? [AXUIElement] {
            for child in list {
                result.append(contentsOf: texts(in: child, depth: depth + 1))
                if result.count > Self.textLimit { return result }
            }
        }

        return result
    }

    /// Приложение по имени из баннера.
    ///
    /// Имя в баннере берётся из локализации самого приложения и совпадает
    /// с `localizedName` не всегда: бывает и «Telegram Desktop» против
    /// «Telegram», и разный регистр. Промах здесь стоит дорого — без
    /// приложения нет ни значка, ни цвета, ни снятия по прочтении, — поэтому
    /// ищем в четыре захода, от точного совпадения к нестрогому.
    /// Иконка приложения по имени из баннера.
    ///
    /// Уведомления с айфона приходят от приложений, которых на Маке может
    /// не быть запущено вовсе — а часто и не установлено. Поэтому сначала
    /// ищем среди запущенных, потом среди установленных на диске, и только
    /// потом сдаёмся.
    static func icon(named name: String) -> NSImage? {
        if let running = application(named: name) { return running.icon }
        if let url = installedApplication(named: name) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        // Уведомления с айфона приходят от приложений, которых на Маке нет
        // и быть не может. Пустое место в карточке — потеря: по значку
        // и узнают, откуда пришло. Рисуем свой: буква и цвет от имени.
        return monogram(for: name)
    }

    /// Значок из первой буквы имени. Цвет берётся из самого имени, поэтому
    /// одно и то же приложение всегда одного цвета, а разные — разного.
    static func monogram(for name: String) -> NSImage? {
        let letter = name.trimmingCharacters(in: .whitespaces).first.map(String.init)?.uppercased()
        guard let letter, !letter.isEmpty else { return nil }

        if let cached = monograms[name] { return cached }

        let side: CGFloat = 64
        let image = NSImage(size: CGSize(width: side, height: side))
        image.lockFocus()

        let hue = CGFloat(abs(name.hashValue % 360)) / 360
        let background = NSColor(hue: hue, saturation: 0.55, brightness: 0.72, alpha: 1)
        let path = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: side, height: side),
            xRadius: side * 0.23, yRadius: side * 0.23
        )
        background.setFill()
        path.fill()

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: side * 0.5, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style,
        ]
        let text = letter as NSString
        let height = text.size(withAttributes: attributes).height
        text.draw(
            in: NSRect(x: 0, y: (side - height) / 2, width: side, height: height),
            withAttributes: attributes
        )

        image.unlockFocus()
        monograms[name] = image
        return image
    }

    private nonisolated(unsafe) static var monograms: [String: NSImage] = [:]

    /// Нарисованный нами значок или настоящая иконка приложения.
    /// В диагностике это единственный способ отличить «иконку не нашли»
    /// от «иконки нет вовсе».
    static func isMonogram(_ image: NSImage?) -> Bool {
        guard let image else { return false }
        return monograms.values.contains { $0 === image }
    }

    /// Установленные приложения: имя → бандл.
    ///
    /// Перебор папок стоит десятки миллисекунд, а состав меняется редко,
    /// поэтому список собирается один раз и живёт до перезапуска.
    private nonisolated(unsafe) static var installed: [String: URL]?
    private nonisolated(unsafe) static var scanStarted = false
    private nonisolated(unsafe) static let scanLock = NSLock()

    /// Собрать список установленных приложений заранее и не на главном потоке.
    ///
    /// Обход папок с чтением таблиц перевода у сотни приложений стоит почти
    /// секунду. На главном потоке это была бы секунда заминки ровно в тот
    /// момент, когда пришло первое уведомление, — то есть на самом видном
    /// месте. Пока список не готов, обходимся запущенными приложениями
    /// и нарисованной буквой.
    nonisolated static func warmUp(then finished: (@Sendable @MainActor () -> Void)? = nil) {
        scanLock.lock()

        // Список уже собран — звать обратно можно сразу.
        if installed != nil {
            scanLock.unlock()
            if let finished {
                DispatchQueue.main.async { MainActor.assumeIsolated { finished() } }
            }
            return
        }

        // Сбор уже идёт — встаём в очередь, а не запускаем второй.
        if let finished { waiters.append(finished) }
        if scanStarted {
            scanLock.unlock()
            return
        }
        scanStarted = true
        scanLock.unlock()

        DispatchQueue.global(qos: .utility).async {
            let found = scanApplications()

            scanLock.lock()
            installed = found
            let callbacks = waiters
            waiters.removeAll()
            scanLock.unlock()

            guard !callbacks.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { callbacks.forEach { $0() } }
            }
        }
    }

    private nonisolated(unsafe) static var waiters: [@Sendable @MainActor () -> Void] = []

    private nonisolated static func installedApplication(named name: String) -> URL? {
        scanLock.lock()
        let installed = self.installed
        scanLock.unlock()

        // Список ещё собирается — значок появится, когда он будет готов.
        guard let installed else {
            warmUp()
            return nil
        }

        let target = normalized(name)
        guard !target.isEmpty else { return nil }

        if let exact = installed[target] { return exact }
        // Нестрого: «WhatsApp Messenger» на телефоне и «WhatsApp» на Маке.
        // Короткие имена сюда не пускаем: совпадение по трём буквам —
        // это уже не то же приложение, а случайность.
        guard target.count >= 4 else { return nil }
        return installed.first { key, _ in
            key.count >= 4 && (key.hasPrefix(target) || target.hasPrefix(key))
        }?.value
    }

    private nonisolated static func scanApplications() -> [String: URL] {
        let roots = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ].map { URL(fileURLWithPath: $0) }

        // Заглядываем и на уровень внутрь: Setapp, Adobe и наборы утилит
        // держат приложения в своей папке, и снаружи их не видно.
        var folders = roots
        for root in roots {
            let items = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            folders += items.filter { $0.pathExtension != "app" }
        }

        var result: [String: URL] = [:]
        for folder in folders {
            let items = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []

            for url in items where url.pathExtension == "app" {
                // Имя в баннере — то, которое видит человек, а оно переведено:
                // на русской системе «Сообщения», а в Info.plist «Messages».
                // `displayName(atPath:)` отдаёт именно видимое имя.
                var names = [
                    FileManager.default.displayName(atPath: url.path),
                    Bundle(url: url)?.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
                    Bundle(url: url)?.displayName,
                    url.deletingPathExtension().lastPathComponent,
                ].compactMap { $0 }
                names += localizedNames(of: url)

                for name in names {
                    let key = normalized(name)
                    guard !key.isEmpty, result[key] == nil else { continue }
                    result[key] = url
                }
            }
        }
        return result
    }

    /// Проверка поиска иконок: для каждого установленного приложения берётся
    /// имя на языке системы — то самое, которым его назовёт баннер, — и
    /// проверяется, находится ли по нему настоящая иконка.
    ///
    /// Без такой проверки поломка не видна: в диагностике одного уведомления
    /// «значок найден» стоит и тогда, когда найдена нарисованная буква.
    static func iconAudit() -> [(name: String, found: Bool, monogram: Bool)] {
        if installed == nil { installed = scanApplications() }
        let language = Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en"

        var seen = Set<String>()
        var result: [(String, Bool, Bool)] = []

        for url in Set((installed ?? [:]).values).sorted(by: { $0.path < $1.path }) {
            let name = systemLanguageName(of: url, language: language)
                ?? url.deletingPathExtension().lastPathComponent
            guard seen.insert(name).inserted else { continue }

            let icon = self.icon(named: name)
            result.append((name, icon != nil, isMonogram(icon)))
        }
        return result
    }

    /// Имя приложения на языке системы — то, которым его назовёт баннер.
    static func systemLanguageName(of url: URL, language: String) -> String? {
        let loctable = url.appendingPathComponent("Contents/Resources/InfoPlist.loctable")
        guard let table = NSDictionary(contentsOf: loctable) as? [String: [String: Any]],
              let entry = table[language]
        else { return nil }

        return (entry["CFBundleDisplayName"] ?? entry["CFBundleName"]) as? String
    }

    /// Все имена, под которыми приложение известно на разных языках.
    ///
    /// В баннере имя переведённое, и взять его из `Info.plist` нельзя: там
    /// лежит английское. Перевод хранится отдельно — у современных приложений
    /// одной таблицей `InfoPlist.loctable` со всеми языками сразу, у старых
    /// файлом на язык. Ни `displayName(atPath:)`, ни `localizedInfoDictionary`
    /// до него не добираются: они смотрят на язык нашего процесса, а не на
    /// содержимое чужого бандла. Из-за этого «Редактор скриптов» не находил
    /// сам «Script Editor», и уведомление оставалось без иконки.
    private nonisolated static func localizedNames(of url: URL) -> [String] {
        let resources = url.appendingPathComponent("Contents/Resources")
        var names: [String] = []

        let loctable = resources.appendingPathComponent("InfoPlist.loctable")
        if let table = NSDictionary(contentsOf: loctable) as? [String: [String: Any]] {
            for entry in table.values {
                names += [entry["CFBundleDisplayName"], entry["CFBundleName"]]
                    .compactMap { $0 as? String }
            }
            return names
        }

        // Старый формат — по файлу на язык. Заглядываем сюда только когда
        // общей таблицы нет: это десятки лишних чтений на приложение.
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: resources, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []

        for folder in folders.prefix(40) where folder.pathExtension == "lproj" {
            let strings = folder.appendingPathComponent("InfoPlist.strings")
            guard let table = NSDictionary(contentsOf: strings) as? [String: String] else { continue }
            names += [table["CFBundleDisplayName"], table["CFBundleName"]].compactMap { $0 }
        }
        return names
    }

    private static func application(named name: String) -> NSRunningApplication? {
        let target = normalized(name)
        guard !target.isEmpty else { return nil }

        // Приложения с окнами важнее фоновых: баннеры шлют именно они.
        let running = NSWorkspace.shared.runningApplications
            .sorted { lhs, rhs in
                (lhs.activationPolicy == .regular ? 0 : 1) < (rhs.activationPolicy == .regular ? 0 : 1)
            }

        func find(_ matches: (String) -> Bool) -> NSRunningApplication? {
            running.first { application in
                let names = [
                    application.localizedName,
                    application.bundleURL.flatMap { Bundle(url: $0)?.displayName },
                ].compactMap { $0.map(normalized) }.filter { !$0.isEmpty }
                return names.contains(where: matches)
            }
        }

        // Нестрогие правила — только для имён подлиннее. Пустая строка
        // содержится в любой, а среди запущенных всегда есть фоновые службы
        // с именем из одних символов: без этого условия иконку получал
        // первый попавшийся системный процесс, и она была не та.
        func loose(_ candidate: String) -> Bool {
            candidate.count >= 4 && target.count >= 4
        }

        return find { $0 == target }
            ?? find { loose($0) && $0.hasPrefix(target) }
            ?? find { loose($0) && target.hasPrefix($0) }
            ?? find { loose($0) && ($0.contains(target) || target.contains($0)) }
    }

    /// Имя без регистра, пробелов и служебных знаков: «Telegram Desktop»
    /// и «telegram-desktop» должны считаться одним и тем же.
    private nonisolated static func normalized(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
