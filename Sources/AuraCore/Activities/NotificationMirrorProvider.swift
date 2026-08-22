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
        var icon: NSImage?
        var tint: Color
        var receivedAt: Date

        static func == (lhs: Message, rhs: Message) -> Bool { lhs.id == rhs.id }
    }

    /// Последнее пришедшее — его и показывает карточка события.
    @Published private(set) var latest: Message?
    /// Сколько непрочитанного накопилось по каждому приложению.
    @Published private(set) var unread: [String: Int] = [:]

    /// Пришло новое уведомление — острову пора вырасти.
    var onMessage: ((Message) -> Void)?

    private let center: ActivityCenter
    private let settings: SettingsStore
    private var observer: AXObserver?
    private var element: AXUIElement?
    private var seen: [String] = []
    /// Окно последнего баннера — через него работает ответ.
    private var latestBanner: AXUIElement?
    /// Имя приложения из баннера → его идентификатор.
    private var bundleIDs: [String: String] = [:]

    private let bannerHost = "com.apple.notificationcenterui"

    init(center: ActivityCenter, settings: SettingsStore) {
        self.center = center
        self.settings = settings
    }

    var isAvailable: Bool { AXIsProcessTrusted() }

    /// Подставить уведомление вручную — для снимков интерфейса и тестов.
    func inject(_ message: Message?) {
        latest = message
    }

    func injectUnread(app: String, count: Int) {
        unread[app] = count
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

        AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, context)
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        self.observer = observer

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
        seen.removeAll()

        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for app in unread.keys { center.remove(id: Self.activityID(for: app)) }
        unread.removeAll()
        bundleIDs.removeAll()
        latest = nil
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
        guard unread[app] != nil else { return }
        unread[app] = nil
        bundleIDs[app] = nil
        center.remove(id: Self.activityID(for: app))
        if latest?.app == app { latest = nil }
    }

    /// Имя приложения по идентификатору активности — по нему строка
    /// в раскрытой панели умеет пометить себя прочитанной.
    static func appName(fromActivityID id: String) -> String? {
        let prefix = "notification."
        guard id.hasPrefix(prefix) else { return nil }
        return String(id.dropFirst(prefix.count))
    }

    func markAllRead() {
        for app in unread.keys { center.remove(id: Self.activityID(for: app)) }
        unread.removeAll()
        bundleIDs.removeAll()
        latest = nil
    }

    private static func activityID(for app: String) -> String {
        "notification.\(app)"
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
            guard let content = Self.content(from: texts) else { return }
            self.present(content)
        }
    }

    private func present(_ content: Content) {
        // Один и тот же баннер система иногда пересоздаёт.
        let key = "\(content.app)|\(content.sender)|\(content.body ?? "")"
        guard !seen.contains(key) else { return }
        seen.append(key)
        if seen.count > 40 { seen.removeFirst() }

        settings.rememberNotificationApp(content.app)
        let rule = settings.notificationRule(for: content.app)
        guard rule != "off" else { return }

        let application = Self.application(named: content.app)
        let icon = Self.icon(named: content.app)
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
            icon: icon,
            tint: tint,
            receivedAt: Date()
        )

        latest = message

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

        unread[content.app, default: 0] += 1
        bundleIDs[content.app] = application?.bundleIdentifier

        // Значок в компактном виде: иконка слева, счётчик справа. Живёт,
        // пока пользователь не откроет приложение.
        center.upsert(
            Activity(
                id: Self.activityID(for: content.app),
                title: message.sender,
                subtitle: message.body ?? kind.wording,
                symbol: kind.symbol,
                // Счётчик непрочитанных — белый. Цвет приложения работает
                // на обводке карточки, а в компактном виде рядом с самой
                // иконкой он только спорит с ней.
                tint: .white,
                artwork: icon,
                priority: .important,
                indicator: .text("\(unread[content.app] ?? 1)")
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
        guard let url = installedApplication(named: name) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Установленные приложения: имя → бандл.
    ///
    /// Перебор папок стоит десятки миллисекунд, а состав меняется редко,
    /// поэтому список собирается один раз и живёт до перезапуска.
    private nonisolated(unsafe) static var installed: [String: URL]?

    private static func installedApplication(named name: String) -> URL? {
        if installed == nil { installed = scanApplications() }
        let target = normalized(name)
        guard !target.isEmpty, let installed else { return nil }

        if let exact = installed[target] { return exact }
        // Нестрого: «WhatsApp Messenger» на телефоне и «WhatsApp» на Маке.
        return installed.first { $0.key.hasPrefix(target) || target.hasPrefix($0.key) }?.value
    }

    private static func scanApplications() -> [String: URL] {
        let folders = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            NSHomeDirectory() + "/Applications",
        ].map { URL(fileURLWithPath: $0) }

        var result: [String: URL] = [:]
        for folder in folders {
            let items = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []

            for url in items where url.pathExtension == "app" {
                let names = [
                    Bundle(url: url)?.displayName,
                    url.deletingPathExtension().lastPathComponent,
                ].compactMap { $0 }

                for name in names {
                    let key = normalized(name)
                    guard !key.isEmpty, result[key] == nil else { continue }
                    result[key] = url
                }
            }
        }
        return result
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
                ].compactMap { $0.map(normalized) }
                return names.contains(where: matches)
            }
        }

        return find { $0 == target }
            ?? find { $0.hasPrefix(target) }
            ?? find { target.hasPrefix($0) }
            ?? find { $0.contains(target) || target.contains($0) }
    }

    /// Имя без регистра, пробелов и служебных знаков: «Telegram Desktop»
    /// и «telegram-desktop» должны считаться одним и тем же.
    private static func normalized(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
