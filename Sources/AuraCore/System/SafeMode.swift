import Foundation

/// Аварийный режим: три падения подряд при старте — запускаемся без
/// источников.
///
/// Падение при запуске — худший вид поломки: приложение не успевает
/// показать ни настроек, ни меню, и починить его можно только из терминала.
/// Так и было с падением на музыке: тап спектра открывался сразу, процесс
/// умирал, и пользователю оставалось разве что удалить программу.
///
/// Метка ставится в начале запуска и снимается, когда приложение прожило
/// достаточно, чтобы считаться живым. Если метка на месте — значит, прошлый
/// запуск до этого не дожил.
@MainActor
enum SafeMode {
    private static let key = "неудачныхЗапусков"
    /// Сколько прожить, чтобы запуск засчитался удачным.
    private static let survival: TimeInterval = 12
    /// После стольких падений подряд источники выключаются.
    static let threshold = 3

    private static var defaults: UserDefaults { .standard }

    /// Сколько запусков подряд не дожили до конца.
    static var failedLaunches: Int { defaults.integer(forKey: key) }

    /// Нужно ли стартовать без источников.
    static var isActive: Bool { failedLaunches >= threshold }

    /// Отметить начало запуска и завести таймер снятия метки.
    static func beginLaunch() {
        defaults.set(failedLaunches + 1, forKey: key)

        DispatchQueue.main.asyncAfter(deadline: .now() + survival) {
            MainActor.assumeIsolated { markSurvived() }
        }
    }

    /// Приложение прожило достаточно — предыдущие неудачи больше не в счёт.
    static func markSurvived() {
        defaults.removeObject(forKey: key)
    }

    /// Пользователь починил настройки и хочет обратно.
    static func reset() {
        defaults.removeObject(forKey: key)
    }
}
