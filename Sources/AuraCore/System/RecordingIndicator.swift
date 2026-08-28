import AppKit
import ApplicationServices

/// Что именно горит в строке меню.
///
/// macOS показывает точку, когда приложение слушает звук или снимает экран,
/// но не говорит снаружи, кто и почему. Зато пункт «Пункта управления»
/// подписан для VoiceOver — а Универсальный доступ у нас уже есть.
///
/// Нужно это для разбора: пока не знаешь, что зажигает индикатор, чинить
/// можно бесконечно и не туда.
@MainActor
enum RecordingIndicator {
    /// Подписи всех пунктов «Пункта управления» в строке меню.
    static func labels() -> [String] {
        guard AXIsProcessTrusted() else { return ["нет доступа к Универсальному доступу"] }

        let hosts = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.controlcenter"
        )
        guard let host = hosts.first else { return ["Пункт управления не запущен"] }

        let application = AXUIElementCreateApplication(host.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXChildrenAttribute as CFString, &value
        ) == .success, let children = value as? [AXUIElement] else { return ["нет дочерних элементов"] }

        var result: [String] = []
        for child in children {
            collect(from: child, into: &result)
        }
        return result
    }

    private static func collect(from element: AXUIElement, into result: inout [String], depth: Int = 0) {
        guard depth < 4, result.count < 40 else { return }

        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = (roleValue as? String) ?? ""

        if role == kAXMenuBarItemRole || role == "AXMenuExtra" || role == kAXButtonRole {
            let parts = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                .compactMap { key -> String? in
                    var text: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(
                        element, key as CFString, &text
                    ) == .success else { return nil }
                    let string = text as? String
                    return (string?.isEmpty == false) ? string : nil
                }
            if !parts.isEmpty { result.append(parts.joined(separator: " · ")) }
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &children
        ) == .success, let list = children as? [AXUIElement] else { return }

        for child in list { collect(from: child, into: &result, depth: depth + 1) }
    }
}
