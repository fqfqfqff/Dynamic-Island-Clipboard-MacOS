import AppKit
import ApplicationServices
import CoreBluetooth

/// Состояние всех разрешений, которые нужны Aura.
///
/// Проверки собраны в одном месте, потому что каждое разрешение выясняется
/// по-своему: одно спрашивается напрямую, другое видно только по факту
/// удачного обращения, третье — по наличию файла.
@MainActor
enum PermissionStatus {
    enum State {
        case granted
        case denied
        case unknown

        var isGranted: Bool { self == .granted }
    }

    /// Управление чужими приложениями: вставка из буфера, зеркало уведомлений.
    static var accessibility: State {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// Разрешение на управление плеерами. Узнаётся только по факту:
    /// либо мы уже получили от плеера ответ, либо получили отказ.
    static func automation(settings: SettingsStore, media: NowPlayingProvider) -> State {
        if media.accessDenied || settings.musicAccessBlocked { return .denied }
        return media.nowPlaying?.canControl == true ? .granted : .unknown
    }

    /// Запись звука для полосок эквалайзера.
    static func audio(spectrum: AudioSpectrumMonitor, settings: SettingsStore) -> State {
        guard settings.reactToAudio else { return .unknown }
        return spectrum.isRunning ? .granted : .unknown
    }

    static var bluetooth: State {
        switch CBManager.authorization {
        case .allowedAlways: .granted
        case .denied, .restricted: .denied
        default: .unknown
        }
    }

    /// Полный доступ к диску — только ради режима фокусирования.
    static var fullDisk: State {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        return (try? Data(contentsOf: url)) != nil ? .granted : .denied
    }

    static var screensaverInstalled: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Screen Savers/Aura.saver")
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Открытие нужного раздела настроек

    static func open(_ pane: Pane) {
        guard let url = URL(string: pane.link) else { return }
        NSWorkspace.shared.open(url)
    }

    enum Pane {
        case accessibility
        case automation
        case audio
        case bluetooth
        case fullDisk
        case screensaver

        var link: String {
            let prefix = "x-apple.systempreferences:com.apple.preference.security?"
            switch self {
            case .accessibility: return prefix + "Privacy_Accessibility"
            case .automation: return prefix + "Privacy_Automation"
            case .audio: return prefix + "Privacy_Microphone"
            case .bluetooth: return prefix + "Privacy_Bluetooth"
            case .fullDisk: return prefix + "Privacy_AllFiles"
            case .screensaver: return "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"
            }
        }
    }
}
