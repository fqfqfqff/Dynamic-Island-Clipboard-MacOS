import Foundation

/// Перевод строк интерфейса.
///
/// Обёртка нужна, чтобы не таскать `bundle: .module` по всему коду: в пакете
/// SwiftPM ресурсы лежат в отдельном бандле, и без явного указания система
/// ищет переводы не там.
///
/// Здесь же живёт выбранный язык. Подмена делается на уровне бандла, а не
/// через `AppleLanguages`: тот вариант требует перезапуска, а переключатель
/// в настройках должен срабатывать сразу.
enum Localization {
    /// "system", "ru" или "en".
    ///
    /// Пишется только с главного потока — из настроек, — читается отовсюду,
    /// поэтому обычная статическая переменная без изоляции.
    nonisolated(unsafe) static var language = "system" {
        didSet {
            guard language != oldValue else { return }
            cached = nil
        }
    }

    /// Поиск нужного `.lproj` стоит обращения к файловой системе, а строки
    /// берутся на каждую отрисовку.
    private nonisolated(unsafe) static var cached: Bundle?

    static var bundle: Bundle {
        if let cached { return cached }

        let resolved: Bundle
        if language != "system",
           let path = Bundle.module.path(forResource: language, ofType: "lproj"),
           let localized = Bundle(path: path) {
            resolved = localized
        } else {
            resolved = .module
        }
        cached = resolved
        return resolved
    }
}

func t(_ key: String, _ fallback: String) -> String {
    let value = Localization.bundle.localizedString(forKey: key, value: fallback, table: nil)
    return value == key ? fallback : value
}

extension Bundle {
    /// Имя, которым приложение представляется пользователю.
    var displayName: String? {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String
    }
}
