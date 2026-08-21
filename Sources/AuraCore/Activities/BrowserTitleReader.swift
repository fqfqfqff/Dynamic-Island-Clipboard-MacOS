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

    /// Заголовок активной вкладки. Требует разрешения на управление браузером;
    /// при отказе просто отдаёт nil, и плеер покажет имя приложения.
    ///
    /// Выполняется в акторе, а не на главном потоке. Раньше `NSAppleScript`
    /// звался прямо из опроса плеера: задумавшийся браузер — а он задумывается
    /// на каждом тяжёлом сайте — подвешивал вместе с собой весь интерфейс.
    static func activeTabTitle(bundleID: String?, runner: AppleScriptRunner) async -> String? {
        guard let bundleID, let name = browsers[bundleID] else { return nil }

        let source = name == "Safari"
            ? "tell application \"Safari\" to return name of current tab of window 1"
            : "tell application \"\(name)\" to return title of active tab of window 1"

        guard case .success(let title) = await runner.run(source: source, key: "tab.\(name)"),
              !title.isEmpty else { return nil }

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
