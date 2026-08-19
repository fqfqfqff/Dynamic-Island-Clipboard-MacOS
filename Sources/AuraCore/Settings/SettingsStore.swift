import SwiftUI

/// Настройки приложения. Всё, что можно покрутить, живёт здесь и сразу
/// применяется к вырезу — без перезапуска.
@MainActor
final class SettingsStore: ObservableObject {
    // Внешний вид
    @Published var bottomCornerRadius: Double { didSet { save(bottomCornerRadius, "bottomCornerRadius") } }
    @Published var accessorySlotWidth: Double { didSet { save(accessorySlotWidth, "accessorySlotWidth") } }
    @Published var expandedWidth: Double { didSet { save(expandedWidth, "expandedWidth") } }
    @Published var expandedHeight: Double { didSet { save(expandedHeight, "expandedHeight") } }
    @Published var backgroundOpacity: Double { didSet { save(backgroundOpacity, "backgroundOpacity") } }
    @Published var showWings: Bool { didSet { save(showWings, "showWings") } }

    @Published var showNotch: Bool { didSet { save(showNotch, "showNotch") } }
    @Published var paused: Bool { didSet { save(paused, "paused") } }

    // Поведение
    @Published var reactToProximity: Bool { didSet { save(reactToProximity, "reactToProximity") } }
    /// Радиус, с которого остров начинает реагировать на курсор.
    @Published var proximityReach: Double { didSet { save(proximityReach, "proximityReach") } }
    /// Множитель длительности анимаций: 0.5 — вдвое быстрее, 2 — вдвое медленнее.
    @Published var animationSpeed: Double { didSet { save(animationSpeed, "animationSpeed") } }
    /// Задержка перед раскрытием по наведению.
    @Published var hoverDelay: Double { didSet { save(hoverDelay, "hoverDelay") } }
    /// Автоматически сворачивать раскрытую панель через столько секунд.
    @Published var autoCollapseAfter: Double { didSet { save(autoCollapseAfter, "autoCollapseAfter") } }
    @Published var showChevronHint: Bool { didSet { save(showChevronHint, "showChevronHint") } }
    @Published var showShadow: Bool { didSet { save(showShadow, "showShadow") } }
    @Published var showBorder: Bool { didSet { save(showBorder, "showBorder") } }
    @Published var backdropBlur: Double { didSet { save(backdropBlur, "backdropBlur") } }
    /// Показывать оставшееся время вместо прошедшего.
    @Published var showRemainingTime: Bool { didSet { save(showRemainingTime, "showRemainingTime") } }
    /// Что показывать в правом компактном слоте.
    @Published var trailingSlotStyle: String { didSet { save(trailingSlotStyle, "trailingSlotStyle") } }
    @Published var expandOnHover: Bool { didSet { save(expandOnHover, "expandOnHover") } }
    @Published var hideInFullScreen: Bool { didSet { save(hideInFullScreen, "hideInFullScreen") } }
    @Published var virtualNotchWidth: Double { didSet { save(virtualNotchWidth, "virtualNotchWidth") } }

    // Источники активностей
    @Published var enableMusic: Bool { didSet { save(enableMusic, "enableMusic") } }
    @Published var enableVolume: Bool { didSet { save(enableVolume, "enableVolume") } }
    @Published var enableScreenshots: Bool { didSet { save(enableScreenshots, "enableScreenshots") } }
    @Published var enableBattery: Bool { didSet { save(enableBattery, "enableBattery") } }
    @Published var enableBluetooth: Bool { didSet { save(enableBluetooth, "enableBluetooth") } }
    @Published var enableNotifications: Bool { didSet { save(enableNotifications, "enableNotifications") } }
    @Published var enableFocus: Bool { didSet { save(enableFocus, "enableFocus") } }

    @Published var reactToAudio: Bool { didSet { save(reactToAudio, "reactToAudio") } }

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
    @Published var didAskAccessibility: Bool { didSet { save(didAskAccessibility, "didAskAccessibility") } }
    @Published var musicAccessBlocked: Bool { didSet { save(musicAccessBlocked, "musicAccessBlocked") } }

    // Буфер обмена
    @Published var clipboardLimit: Int { didSet { save(clipboardLimit, "clipboardLimit") } }
    @Published var persistClipboard: Bool { didSet { save(persistClipboard, "persistClipboard") } }
    @Published var autoPaste: Bool { didSet { save(autoPaste, "autoPaste") } }
    @Published var archiveEverything: Bool { didSet { save(archiveEverything, "archiveEverything") } }

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
        expandedHeight = double("expandedHeight", 272)
        backgroundOpacity = double("backgroundOpacity", 1)
        showWings = bool("showWings", true)

        showNotch = bool("showNotch", true)
        paused = bool("paused", false)
        reactToProximity = bool("reactToProximity", true)
        proximityReach = double("proximityReach", 180)
        animationSpeed = double("animationSpeed", 1)
        hoverDelay = double("hoverDelay", 0)
        autoCollapseAfter = double("autoCollapseAfter", 0)
        showChevronHint = bool("showChevronHint", true)
        showShadow = bool("showShadow", true)
        showBorder = bool("showBorder", false)
        backdropBlur = double("backdropBlur", 48)
        showRemainingTime = bool("showRemainingTime", false)
        trailingSlotStyle = defaults.string(forKey: "trailingSlotStyle") ?? "bars"
        expandOnHover = bool("expandOnHover", true)
        hideInFullScreen = bool("hideInFullScreen", true)
        virtualNotchWidth = double("virtualNotchWidth", 190)

        enableMusic = bool("enableMusic", true)
        enableVolume = bool("enableVolume", true)
        enableScreenshots = bool("enableScreenshots", true)
        enableBattery = bool("enableBattery", true)
        enableBluetooth = bool("enableBluetooth", true)
        enableNotifications = bool("enableNotifications", false)
        enableFocus = bool("enableFocus", true)

        reactToAudio = bool("reactToAudio", true)

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

        didAskAccessibility = bool("didAskAccessibility", false)
        musicAccessBlocked = bool("musicAccessBlocked", false)

        clipboardLimit = defaults.object(forKey: "clipboardLimit") as? Int ?? 100
        persistClipboard = bool("persistClipboard", true)
        autoPaste = bool("autoPaste", true)
        archiveEverything = bool("archiveEverything", true)
    }

    func resetToDefaults() {
        bottomCornerRadius = 22
        accessorySlotWidth = 44
        expandedWidth = 320
        expandedHeight = 272
        backgroundOpacity = 1
        showWings = true
        showNotch = true
        paused = false
        reactToProximity = true
        proximityReach = 180
        animationSpeed = 1
        hoverDelay = 0
        autoCollapseAfter = 0
        showChevronHint = true
        showShadow = true
        showBorder = false
        backdropBlur = 48
        showRemainingTime = false
        trailingSlotStyle = "bars"
        expandOnHover = true
        hideInFullScreen = true
        virtualNotchWidth = 190
        enableMusic = true
        enableVolume = true
        enableScreenshots = true
        enableBattery = true
        enableBluetooth = true
        enableNotifications = false
        enableFocus = true
        clipboardLimit = 100
        persistClipboard = true
        autoPaste = true
        archiveEverything = true
        forgetPermissionPrompts()
    }

    /// Забыть, что разрешения уже спрашивали, — после этого Aura спросит снова.
    func forgetPermissionPrompts() {
        didAskAccessibility = false
        musicAccessBlocked = false
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

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
