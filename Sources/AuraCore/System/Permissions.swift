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
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
