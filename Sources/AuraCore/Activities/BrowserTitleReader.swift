import AppKit

/// Заголовок вкладки браузера — единственный доступный «трек» для видео и
/// музыки, которые играют в вебе.
enum BrowserTitleReader {
    private static let browsers: [String: String] = [
        "com.google.Chrome": "Google Chrome",
        "com.apple.Safari": "Safari",
        "com.microsoft.edgemac": "Microsoft Edge",
        "company.thebrowser.Browser": "Arc",
        "ru.yandex.desktop.yandex-browser": "Yandex",
    ]

    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return browsers[bundleID] != nil
    }

    /// Возвращает заголовок активной вкладки. Требует разрешения на управление
    /// браузером; при отказе просто отдаёт nil, и плеер покажет имя приложения.
    static func activeTabTitle(bundleID: String?) -> String? {
        guard let bundleID, let name = browsers[bundleID] else { return nil }

        let source = name == "Safari"
            ? "tell application \"Safari\" to return name of current tab of window 1"
            : "tell application \"\(name)\" to return title of active tab of window 1"

        var error: NSDictionary?
        let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard error == nil, let title = output?.stringValue, !title.isEmpty else { return nil }

        return cleaned(title)
    }

    /// Браузеры дописывают в заголовок служебные хвосты — они в вырезе не нужны.
    private static func cleaned(_ title: String) -> String {
        var result = title
        for suffix in [" - YouTube", " — YouTube", " - Twitch", " и другие видео"] {
            if result.hasSuffix(suffix) {
                result.removeLast(suffix.count)
            }
        }
        if result.hasPrefix("(") , let range = result.range(of: ") ") {
            // «(3) Название» — счётчик непрочитанного
            result = String(result[range.upperBound...])
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
