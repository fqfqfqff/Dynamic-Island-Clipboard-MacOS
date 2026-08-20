import AppKit
import ApplicationServices

enum Permissions {
    /// Выдан ли Accessibility. Нужен, чтобы синтезировать ⌘V в чужом приложении.
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Показывает системный запрос. Пользователь всё равно уходит в настройки
    /// руками — macOS не даёт выдать это разрешение из приложения.
    @discardableResult
    static func requestAccessibility() -> Bool {
        // Ключ объявлен в заголовках как переменная, хотя по смыслу константа.
        // Берём его значение здесь и дальше работаем со строкой.
        let key = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
