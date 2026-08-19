import Foundation

/// Панель выреза и окно буфера живут в SwiftUI и не знают про делегата.
/// Вместо прокидывания зависимостей через все слои — два простых сигнала.
public extension Notification.Name {
    static let auraOpenSettings = Notification.Name("aura.openSettings")
    static let auraQuit = Notification.Name("aura.quit")
    static let auraShowOnboarding = Notification.Name("aura.showOnboarding")
}

enum AppActions {
    static func openSettings() {
        NotificationCenter.default.post(name: .auraOpenSettings, object: nil)
    }

    static func quit() {
        NotificationCenter.default.post(name: .auraQuit, object: nil)
    }

    static func showOnboarding() {
        NotificationCenter.default.post(name: .auraShowOnboarding, object: nil)
    }
}
