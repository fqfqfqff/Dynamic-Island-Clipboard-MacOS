import ServiceManagement

/// Автозапуск при входе в систему.
///
/// Работает только для установленной копии: приложение, запущенное из папки
/// сборки, система зарегистрировать откажется.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Aura: автозапуск не изменён — %@", error.localizedDescription)
            return false
        }
    }
}
