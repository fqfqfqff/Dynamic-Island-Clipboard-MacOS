import SwiftUI

/// Настройки приложения. Всё, что можно покрутить, живёт здесь и сразу
/// применяется к вырезу — без перезапуска.
@MainActor
final class SettingsStore: ObservableObject {
    // Внешний вид
    @Published var bottomCornerRadius: Double { didSet { save(bottomCornerRadius, "bottomCornerRadius") } }
    @Published var accessorySlotWidth: Double { didSet { save(accessorySlotWidth, "accessorySlotWidth") } }
    @Published var expandedWidth: Double { didSet { save(expandedWidth, "expandedWidth") } }
    @Published var backgroundOpacity: Double { didSet { save(backgroundOpacity, "backgroundOpacity") } }
    @Published var showWings: Bool { didSet { save(showWings, "showWings") } }

    @Published var showNotch: Bool { didSet { save(showNotch, "showNotch") } }
    /// Сколько настроек показывать: "minimal", "normal" или "all".
    ///
    /// Их больше сорока в девяти разделах, и человеку, который открыл окно
    /// первый раз, это стена. Уровень отсекает лишнее, ничего не выключая.
    @Published var detailLevel: String { didSet { save(detailLevel, "detailLevel") } }

    /// Язык интерфейса: "system", "ru" или "en".
    @Published var language: String {
        didSet {
            save(language, "language")
            Localization.language = language
        }
    }
    @Published var paused: Bool { didSet { save(paused, "paused") } }

    // Поведение
    @Published var scrollSwitchesTrack: Bool { didSet { save(scrollSwitchesTrack, "scrollSwitchesTrack") } }
    @Published var doubleClickTogglesPlayback: Bool { didSet { save(doubleClickTogglesPlayback, "doubleClickTogglesPlayback") } }
    @Published var reactToProximity: Bool { didSet { save(reactToProximity, "reactToProximity") } }
    /// Радиус, с которого остров начинает реагировать на курсор.
    @Published var proximityReach: Double { didSet { save(proximityReach, "proximityReach") } }
    /// Множитель длительности анимаций: 0.5 — вдвое быстрее, 2 — вдвое медленнее.
    @Published var animationSpeed: Double { didSet { save(animationSpeed, "animationSpeed") } }
    /// Задержка перед раскрытием по наведению.
    @Published var hoverDelay: Double { didSet { save(hoverDelay, "hoverDelay") } }
    /// Автоматически сворачивать раскрытую панель через столько секунд.
    @Published var autoCollapseAfter: Double { didSet { save(autoCollapseAfter, "autoCollapseAfter") } }
    /// На сколько точек остров подрастает при наведении.
    @Published var peekGrowth: Double { didSet { save(peekGrowth, "peekGrowth") } }
    /// Вид подсказки под вырезом: "chevron", "line", "dot" или "none".
    @Published var hintStyle: String { didSet { save(hintStyle, "hintStyle") } }
    /// Характер пружин: 0 — движение успокаивается сразу, 1 — заметно
    /// отыгрывает назад.
    @Published var animationBounce: Double { didSet { save(animationBounce, "animationBounce") } }
    @Published var showShadow: Bool { didSet { save(showShadow, "showShadow") } }
    @Published var showBorder: Bool { didSet { save(showBorder, "showBorder") } }
    @Published var backdropBlur: Double { didSet { save(backdropBlur, "backdropBlur") } }
    /// Показывать оставшееся время вместо прошедшего.
    @Published var showRemainingTime: Bool { didSet { save(showRemainingTime, "showRemainingTime") } }
    /// Что показывать в правом компактном слоте.
    @Published var trailingSlotStyle: String { didSet { save(trailingSlotStyle, "trailingSlotStyle") } }
    @Published var expandOnHover: Bool { didSet { save(expandOnHover, "expandOnHover") } }
    @Published var hideInFullScreen: Bool { didSet { save(hideInFullScreen, "hideInFullScreen") } }
    /// Переносить панель на тот экран, где курсор.
    @Published var followMouseScreen: Bool { didSet { save(followMouseScreen, "followMouseScreen") } }
    @Published var virtualNotchWidth: Double { didSet { save(virtualNotchWidth, "virtualNotchWidth") } }

    // Источники активностей
    @Published var enableMusic: Bool { didSet { save(enableMusic, "enableMusic") } }
    /// Слушать ли звук вообще: и полоски спектра, и различение играющего
    /// приложения от молчащего. Пока Aura слушает, macOS держит в строке меню
    /// свой значок «идёт запись» — убрать его можно только перестав слушать.
    /// Макет плеера: «large» — обложка во всю ширину, «compact» — обложка
    /// слева, название и полоса справа. Компактный втрое ниже.
    @Published var playerLayout: String { didSet { save(playerLayout, "playerLayout") } }
    @Published var listenToAudio: Bool { didSet { save(listenToAudio, "listenToAudio") } }
    @Published var enableScreenshots: Bool { didSet { save(enableScreenshots, "enableScreenshots") } }
    @Published var copyScreenshotToClipboard: Bool { didSet { save(copyScreenshotToClipboard, "copyScreenshotToClipboard") } }
    @Published var enableBattery: Bool { didSet { save(enableBattery, "enableBattery") } }
    @Published var enableNotifications: Bool { didSet { save(enableNotifications, "enableNotifications") } }
    @Published var enableFocus: Bool { didSet { save(enableFocus, "enableFocus") } }
    @Published var enableCalendar: Bool { didSet { save(enableCalendar, "enableCalendar") } }
    /// Спрашивать, что делать с файлом, брошенным на вырез.
    @Published var dropShowsMenu: Bool { didSet { save(dropShowsMenu, "dropShowsMenu") } }
    /// Идущие загрузки браузеров.
    @Published var enableDownloads: Bool { didSet { save(enableDownloads, "enableDownloads") } }
    /// Wi-Fi, кабель и режим модема.
    @Published var enableNetwork: Bool { didSet { save(enableNetwork, "enableNetwork") } }

    @Published var reactToAudio: Bool { didSet { save(reactToAudio, "reactToAudio") } }
    /// Ставить на паузу, когда отключили наушники.
    ///
    /// macOS делает это сама, но только для приложений, которые
    /// позаботились: браузер обычно продолжает играть в динамики.
    @Published var pauseOnHeadphonesRemoved: Bool { didSet { save(pauseOnHeadphonesRemoved, "pauseOnHeadphonesRemoved") } }
    /// Дополнять список исполнителей Spotify с публичной страницы трека.
    ///
    /// В AppleScript у Spotify одно поле `artist`, и для трека с несколькими
    /// исполнителями оно отдаёт только первого. Остальных видно на странице
    /// трека — она открыта всем, ключей не нужно.
    @Published var enrichSpotifyArtists: Bool { didSet { save(enrichSpotifyArtists, "enrichSpotifyArtists") } }

    // Уведомления
    /// "card" — вырез вырастает карточкой, "badge" — только значок в компактном виде.
    @Published var notificationStyle: String { didSet { save(notificationStyle, "notificationStyle") } }
    /// Сколько секунд держать карточку. Ноль — до тех пор, пока не прочитают.
    @Published var notificationHold: Double { didSet { save(notificationHold, "notificationHold") } }
    /// Через сколько минут значок непрочитанного гаснет сам. Ноль — никогда.
    @Published var notificationBadgeTTL: Double { didSet { save(notificationBadgeTTL, "notificationBadgeTTL") } }
    /// Насколько крупнее обычного показывать карточку уведомления.
    @Published var notificationScale: Double { didSet { save(notificationScale, "notificationScale") } }
    /// Показывать сам текст сообщения. Выключено — видно только от кого и что
    /// за вложение: вырез видят все, кто смотрит на экран.
    @Published var notificationShowBody: Bool { didSet { save(notificationShowBody, "notificationShowBody") } }
    /// Обводка карточки в цвет иконки приложения.
    @Published var notificationTintFromIcon: Bool { didSet { save(notificationTintFromIcon, "notificationTintFromIcon") } }
    /// Показывать значок, даже когда приложение сейчас открыто.
    ///
    /// По умолчанию да, хотя «правильнее» было бы нет: уведомление от
    /// приложения, в которое человек смотрит, он уже прочитал. Но пропавший
    /// значок — тихая поломка, её не отличить от сломанных уведомлений;
    /// лишний значок виден и убирается одним кликом.
    @Published var notificationBadgeWhenAppOpen: Bool { didSet { save(notificationBadgeWhenAppOpen, "notificationBadgeWhenAppOpen") } }
    /// Правила по приложениям: имя → "card", "badge" или "off".
    /// Снимать значок с самого баннера, когда приложения на Маке нет.
    /// Требует разрешения на запись экрана — и спрашивается оно только
    /// в первый раз, когда иконку действительно негде взять.
    @Published var readIconsFromBanner: Bool { didSet { save(readIconsFromBanner, "readIconsFromBanner") } }
    /// Срезать уголок со значком телефона у снятых значков.
    @Published var trimPhoneBadge: Bool { didSet { save(trimPhoneBadge, "trimPhoneBadge") } }
    /// Молчать карточкой, пока включён режим фокусирования.
    @Published var respectFocus: Bool { didSet { save(respectFocus, "respectFocus") } }
    @Published var notificationRules: [String: String] { didSet { save(notificationRules, "notificationRules") } }
    /// От кого уведомления уже приходили — чтобы в настройках было что настраивать.
    @Published var notificationKnownApps: [String] { didSet { save(notificationKnownApps, "notificationKnownApps") } }

    // Оформление: фон, стекло, акцент
    /// "artwork" — размытая обложка, "gradient" — градиент, "solid" — чёрный.
    @Published var backgroundStyle: String { didSet { save(backgroundStyle, "backgroundStyle") } }
    @Published var gradientPreset: String { didSet { save(gradientPreset, "gradientPreset") } }
    /// "regular", "clear", "tinted" или "off".
    @Published var glassStyle: String { didSet { save(glassStyle, "glassStyle") } }
    /// "artwork" — цвет берётся с обложки, "fixed" — заданный вручную.
    @Published var accentSource: String { didSet { save(accentSource, "accentSource") } }
    @Published var accentHex: String { didSet { save(accentHex, "accentHex") } }
    /// "default", "rounded" или "serif".
    @Published var fontDesign: String { didSet { save(fontDesign, "fontDesign") } }

    // Витрина
    /// "columns" — обложка и текст рядом, "centered" — всё колонкой по центру.
    @Published var showcaseLayout: String { didSet { save(showcaseLayout, "showcaseLayout") } }
    @Published var showcaseClock: Bool { didSet { save(showcaseClock, "showcaseClock") } }

    // Оформление плеера
    @Published var artworkSize: Double { didSet { save(artworkSize, "artworkSize") } }
    @Published var artworkCornerRadius: Double { didSet { save(artworkCornerRadius, "artworkCornerRadius") } }
    @Published var titleFontSize: Double { didSet { save(titleFontSize, "titleFontSize") } }
    @Published var showSeekBar: Bool { didSet { save(showSeekBar, "showSeekBar") } }
    @Published var showControls: Bool { didSet { save(showControls, "showControls") } }
    @Published var showLyrics: Bool { didSet { save(showLyrics, "showLyrics") } }
    @Published var barCount: Int { didSet { save(barCount, "barCount") } }
    /// 0 — чистый чёрный, 1 — обложка во всю подложку.
    @Published var backdropStrength: Double { didSet { save(backdropStrength, "backdropStrength") } }

    // Витрина вместо экрана блокировки
    @Published var showcaseOnIdle: Bool { didSet { save(showcaseOnIdle, "showcaseOnIdle") } }
    @Published var showcaseIdleMinutes: Double { didSet { save(showcaseIdleMinutes, "showcaseIdleMinutes") } }

    // Разрешения: запрашиваем ровно один раз, дальше — только по кнопке.
    @Published var didCompleteOnboarding: Bool { didSet { save(didCompleteOnboarding, "didCompleteOnboarding") } }
    @Published var didAskAccessibility: Bool { didSet { save(didAskAccessibility, "didAskAccessibility") } }
    @Published var musicAccessBlocked: Bool { didSet { save(musicAccessBlocked, "musicAccessBlocked") } }

    // Буфер обмена
    @Published var clipboardLimit: Int { didSet { save(clipboardLimit, "clipboardLimit") } }
    @Published var persistClipboard: Bool { didSet { save(persistClipboard, "persistClipboard") } }
    @Published var autoPaste: Bool { didSet { save(autoPaste, "autoPaste") } }
    /// Вставлять с оформлением: шрифтом, цветом, размером.
    ///
    /// По умолчанию нет. Текст, перенесённый из письма в заметку вместе
    /// с чужим шрифтом, — самая частая причина лезть в «вставить как текст».
    @Published var pasteWithFormatting: Bool { didSet { save(pasteWithFormatting, "pasteWithFormatting") } }
    @Published var archiveEverything: Bool { didSet { save(archiveEverything, "archiveEverything") } }
    /// Из этих приложений в историю ничего не попадает.
    @Published var clipboardExcludedApps: [String] { didSet { save(clipboardExcludedApps, "clipboardExcludedApps") } }
    /// Откуда уже копировали — чтобы было из чего выбирать в настройках.
    @Published var clipboardKnownSources: [String] { didSet { save(clipboardKnownSources, "clipboardKnownSources") } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func double(_ key: String, _ fallback: Double) -> Double {
            defaults.object(forKey: key) as? Double ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }

        bottomCornerRadius = double("bottomCornerRadius", 22)
        accessorySlotWidth = double("accessorySlotWidth", 44)
        expandedWidth = double("expandedWidth", 320)
        backgroundOpacity = double("backgroundOpacity", 1)
        showWings = bool("showWings", true)

        showNotch = bool("showNotch", true)
        language = defaults.string(forKey: "language") ?? "system"
        detailLevel = defaults.string(forKey: "detailLevel") ?? "normal"
        paused = bool("paused", false)
        scrollSwitchesTrack = bool("scrollSwitchesTrack", true)
        doubleClickTogglesPlayback = bool("doubleClickTogglesPlayback", true)
        reactToProximity = bool("reactToProximity", true)
        proximityReach = double("proximityReach", 180)
        animationSpeed = double("animationSpeed", 1)
        hoverDelay = double("hoverDelay", 0)
        autoCollapseAfter = double("autoCollapseAfter", 0)
        peekGrowth = double("peekGrowth", 18)
        animationBounce = double("animationBounce", 0.45)
        // Раньше подсказка была просто галочкой «показывать или нет».
        // Старый выбор переносим, чтобы он не пропал при обновлении.
        if let style = defaults.string(forKey: "hintStyle") {
            hintStyle = style
        } else {
            hintStyle = (defaults.object(forKey: "showChevronHint") as? Bool ?? true)
                ? "chevron" : "none"
        }
        showShadow = bool("showShadow", true)
        showBorder = bool("showBorder", false)
        backdropBlur = double("backdropBlur", 48)
        showRemainingTime = bool("showRemainingTime", false)
        trailingSlotStyle = defaults.string(forKey: "trailingSlotStyle") ?? "bars"
        expandOnHover = bool("expandOnHover", true)
        hideInFullScreen = bool("hideInFullScreen", true)
        followMouseScreen = bool("followMouseScreen", false)
        virtualNotchWidth = double("virtualNotchWidth", 190)

        enableMusic = bool("enableMusic", true)
        playerLayout = defaults.string(forKey: "playerLayout") ?? "large"
        listenToAudio = bool("listenToAudio", true)
        enableScreenshots = bool("enableScreenshots", true)
        copyScreenshotToClipboard = bool("copyScreenshotToClipboard", true)
        enableBattery = bool("enableBattery", true)
        enableNotifications = bool("enableNotifications", false)
        enableFocus = bool("enableFocus", true)
        enableCalendar = bool("enableCalendar", false)
        enableNetwork = bool("enableNetwork", true)
        enableDownloads = bool("enableDownloads", true)
        dropShowsMenu = bool("dropShowsMenu", true)

        reactToAudio = bool("reactToAudio", true)
        pauseOnHeadphonesRemoved = bool("pauseOnHeadphonesRemoved", true)
        enrichSpotifyArtists = bool("enrichSpotifyArtists", true)

        notificationStyle = defaults.string(forKey: "notificationStyle") ?? "card"
        notificationHold = double("notificationHold", 5)
        notificationBadgeTTL = double("notificationBadgeTTL", 10)
        notificationScale = double("notificationScale", 1)
        notificationShowBody = bool("notificationShowBody", true)
        notificationTintFromIcon = bool("notificationTintFromIcon", true)
        notificationBadgeWhenAppOpen = bool("notificationBadgeWhenAppOpen", true)
        readIconsFromBanner = bool("readIconsFromBanner", true)
        trimPhoneBadge = bool("trimPhoneBadge", true)
        respectFocus = bool("respectFocus", true)
        notificationRules = defaults.dictionary(forKey: "notificationRules") as? [String: String] ?? [:]
        notificationKnownApps = defaults.stringArray(forKey: "notificationKnownApps") ?? []

        backgroundStyle = defaults.string(forKey: "backgroundStyle") ?? "artwork"
        gradientPreset = defaults.string(forKey: "gradientPreset") ?? "midnight"
        glassStyle = defaults.string(forKey: "glassStyle") ?? "regular"
        accentSource = defaults.string(forKey: "accentSource") ?? "artwork"
        accentHex = defaults.string(forKey: "accentHex") ?? "#FF2D55"
        fontDesign = defaults.string(forKey: "fontDesign") ?? "default"
        showcaseLayout = defaults.string(forKey: "showcaseLayout") ?? "columns"
        showcaseClock = bool("showcaseClock", true)

        artworkSize = double("artworkSize", 116)
        artworkCornerRadius = double("artworkCornerRadius", 16)
        titleFontSize = double("titleFontSize", 16)
        showSeekBar = bool("showSeekBar", true)
        showControls = bool("showControls", true)
        showLyrics = bool("showLyrics", false)
        barCount = defaults.object(forKey: "barCount") as? Int ?? 5
        backdropStrength = double("backdropStrength", 0.78)
        showcaseOnIdle = bool("showcaseOnIdle", false)
        showcaseIdleMinutes = double("showcaseIdleMinutes", 3)

        didCompleteOnboarding = bool("didCompleteOnboarding", false)
        didAskAccessibility = bool("didAskAccessibility", false)
        musicAccessBlocked = bool("musicAccessBlocked", false)

        clipboardLimit = defaults.object(forKey: "clipboardLimit") as? Int ?? 100
        persistClipboard = bool("persistClipboard", true)
        autoPaste = bool("autoPaste", true)
        pasteWithFormatting = bool("pasteWithFormatting", false)
        archiveEverything = bool("archiveEverything", true)
        clipboardExcludedApps = defaults.stringArray(forKey: "clipboardExcludedApps") ?? []
        clipboardKnownSources = defaults.stringArray(forKey: "clipboardKnownSources") ?? []

        // Наблюдатели свойств в инициализаторе не вызываются, а язык должен
        // примениться до первой отрисовки.
        Localization.language = language
    }

    func resetToDefaults() {
        bottomCornerRadius = 22
        accessorySlotWidth = 44
        expandedWidth = 320
        backgroundOpacity = 1
        showWings = true
        showNotch = true
        language = "system"
        detailLevel = "normal"
        paused = false
        scrollSwitchesTrack = true
        doubleClickTogglesPlayback = true
        reactToProximity = true
        proximityReach = 180
        animationSpeed = 1
        hoverDelay = 0
        autoCollapseAfter = 0
        peekGrowth = 18
        hintStyle = "chevron"
        animationBounce = 0.45
        showShadow = true
        showBorder = false
        backdropBlur = 48
        showRemainingTime = false
        trailingSlotStyle = "bars"
        expandOnHover = true
        hideInFullScreen = true
        followMouseScreen = false
        virtualNotchWidth = 190
        enableMusic = true
        listenToAudio = true
        enableScreenshots = true
        copyScreenshotToClipboard = true
        enableBattery = true
        enableNotifications = false
        enableFocus = true
        enableCalendar = false
        enableNetwork = true
        enableDownloads = true
        dropShowsMenu = true
        notificationStyle = "card"
        notificationHold = 5
        notificationShowBody = true
        notificationTintFromIcon = true
        notificationBadgeWhenAppOpen = true
        notificationRules = [:]
        clipboardLimit = 100
        persistClipboard = true
        autoPaste = true
        pasteWithFormatting = false
        archiveEverything = true
        forgetPermissionPrompts()
    }

    /// Забыть, что разрешения уже спрашивали, — после этого Aura спросит снова.
    func forgetPermissionPrompts() {
        didCompleteOnboarding = false
        didAskAccessibility = false
        musicAccessBlocked = false
    }

    /// Готовые наборы настроек.
    ///
    /// Параметров стало больше сорока, и собрать из них осмысленную
    /// конфигурацию вручную — отдельная работа. Пресеты дают три понятные
    /// точки, от которых можно оттолкнуться.
    enum Preset: String, CaseIterable, Identifiable {
        case minimal = "Минимум"
        case balanced = "Обычный"
        case everything = "Всё сразу"
        case quiet = "Спокойный"

        var id: String { rawValue }

        var explanation: String {
            switch self {
            case .minimal:
                "Плеер и буфер. Ни спектра, ни уведомлений, ни лишнего движения."
            case .balanced:
                "Настройки по умолчанию: музыка, зарядка, громкость, снимки экрана."
            case .everything:
                "Все источники и все жесты, включая уведомления и календарь."
            case .quiet:
                "Всё видно, но ничего не движется: анимации медленные, полоски статичны."
            }
        }
    }

    func apply(_ preset: Preset) {
        switch preset {
        case .minimal:
            enableMusic = true
                enableScreenshots = false
            enableBattery = false
            enableNotifications = false
            enableFocus = false
            enableCalendar = false
            reactToAudio = false
            showShadow = false
            backdropStrength = 0.4

        case .balanced:
            resetToDefaults()

        case .everything:
            enableMusic = true
            enableScreenshots = true
            enableBattery = true
                enableNotifications = true
            enableFocus = true
            enableCalendar = true
            reactToAudio = true
        pauseOnHeadphonesRemoved = true
        enrichSpotifyArtists = true
            showLyrics = true
                scrollSwitchesTrack = true

        case .quiet:
            reactToAudio = false
            reactToProximity = false
            animationSpeed = 1.6
            expandOnHover = false
            hintStyle = "none"
        }
    }

    func resetShowcase() {
        showcaseOnIdle = false
        showcaseIdleMinutes = 3
        reactToAudio = true
        backgroundStyle = "artwork"
        gradientPreset = "midnight"
        glassStyle = "regular"
        accentSource = "artwork"
        accentHex = "#FF2D55"
        fontDesign = "default"
        showcaseLayout = "columns"
        showcaseClock = true
        artworkSize = 116
        artworkCornerRadius = 16
        titleFontSize = 16
        showSeekBar = true
        showControls = true
        showLyrics = false
        barCount = 5
        backdropStrength = 0.78
    }

    /// Запомнить приложение, из которого копировали.
    func rememberClipboardSource(_ app: String) {
        guard !clipboardKnownSources.contains(app) else { return }
        clipboardKnownSources = (clipboardKnownSources + [app]).suffix(30)
    }

    /// Как показывать уведомления от этого приложения.
    func notificationRule(for app: String) -> String {
        notificationRules[app] ?? "card"
    }

    /// Запомнить приложение, чтобы его можно было настроить.
    func rememberNotificationApp(_ app: String) {
        guard !notificationKnownApps.contains(app) else { return }
        // Список не бесконечный: уведомления шлют десятки приложений,
        // а настраивают из них два-три.
        notificationKnownApps = (notificationKnownApps + [app]).suffix(20)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
