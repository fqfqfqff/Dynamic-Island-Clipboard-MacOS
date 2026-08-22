import Foundation

/// Хранилище настроек для тестов.
///
/// Раньше каждый тест заводил домен со своим UUID. Домен — это файл
/// в `~/Library/Preferences`, пишет его cfprefsd и не всегда успевает
/// заметить, что домен уже удалили. За сотни прогонов там накопилось
/// почти четыре тысячи мусорных plist на несколько мегабайт.
///
/// Домен теперь один на весь набор и очищается перед каждой выдачей.
enum TestDefaults {
    static let suite = "dev.kekch.aura.tests"

    static func make() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
