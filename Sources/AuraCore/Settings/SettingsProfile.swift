import AppKit

/// Профиль настроек: весь набор одним файлом.
///
/// Нужен для двух вещей — перенести свою настройку на новую машину после
/// переустановки и показать её кому-то. Сорок с лишним параметров руками
/// не повторишь.
///
/// Сохраняется как обычный JSON, а не как двоичный plist: файл должно быть
/// видно глазами, иначе им не поделишься с толком.
@MainActor
enum SettingsProfile {
    static let fileExtension = "auraprofile"

    /// Ключи системы в наш профиль не попадают: там лежит всё подряд,
    /// от состояния окон до списка недавних файлов.
    private static func isOurs(_ key: String) -> Bool {
        !key.hasPrefix("NS") && !key.hasPrefix("Apple") && !key.hasPrefix("com.apple")
    }

    static func snapshot() -> [String: Any] {
        guard let id = Bundle.main.bundleIdentifier,
              let domain = UserDefaults.standard.persistentDomain(forName: id)
        else { return [:] }
        return domain.filter { isOurs($0.key) }
    }

    static func data() -> Data? {
        let payload: [String: Any] = [
            "приложение": "Aura",
            "версия": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "0",
            "сохранено": ISO8601DateFormatter().string(from: Date()),
            "настройки": snapshot(),
        ]
        return try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Файл

    static func export() {
        guard let data = data() else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Aura.\(fileExtension)"
        panel.allowedContentTypes = []
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Возвращает число применённых параметров.
    @discardableResult
    static func importProfile() -> Int {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = payload["настройки"] as? [String: Any]
        else { return 0 }

        for (key, value) in values where isOurs(key) {
            UserDefaults.standard.set(value, forKey: key)
        }
        UserDefaults.standard.synchronize()
        return values.count
    }

    /// Поделиться профилем, не сохраняя его руками: файл кладётся во временную
    /// папку и уходит в системное меню отправки.
    static func share(from view: NSView) {
        guard let data = data() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Aura.\(fileExtension)")
        try? data.write(to: url)

        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    /// Перезапуск: настройки читаются при старте, и применить чужой профиль
    /// на лету нельзя — половина из них уже разошлась по объектам.
    static func relaunch() {
        guard let path = Bundle.main.bundlePath as String? else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
