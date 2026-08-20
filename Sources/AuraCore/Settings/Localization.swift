import Foundation

/// Перевод строк интерфейса.
///
/// Обёртка нужна, чтобы не таскать `bundle: .module` по всему коду: в пакете
/// SwiftPM ресурсы лежат в отдельном бандле, и без явного указания система
/// ищет переводы не там.
func t(_ key: String, _ fallback: String) -> String {
    let value = Bundle.module.localizedString(forKey: key, value: fallback, table: nil)
    return value == key ? fallback : value
}
