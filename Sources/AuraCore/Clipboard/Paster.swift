import AppKit
import Carbon.HIToolbox

/// Вставка в приложение, с которым сейчас работает пользователь.
///
/// Панель Aura не активирующая, поэтому фокус остаётся у чужого приложения и
/// вставлять можно прямо в него — достаточно синтезировать ⌘V.
enum Paster {
    /// Пауза перед вставкой: пользователь пришёл сюда по ⌥⌘V, и если отправить
    /// событие немедленно, зажатые ⌥ и ⌘ подмешаются в нашу комбинацию.
    private static let modifierReleaseDelay: TimeInterval = 0.18

    /// Ответ кэшируется: `AXIsProcessTrusted` — обращение к системной службе,
    /// а SwiftUI спрашивает об этом на каждой перерисовке.
    @MainActor
    private static var cached: (value: Bool, checkedAt: Date)?

    @MainActor
    static var canPaste: Bool {
        if let cached, Date().timeIntervalSince(cached.checkedAt) < 2, cached.value {
            return true
        }
        let value = Permissions.isAccessibilityTrusted
        cached = (value, Date())
        return value
    }

    @MainActor
    static func pasteIntoFrontmostApp() {
        guard canPaste else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + modifierReleaseDelay) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let key = CGKeyCode(kVK_ANSI_V)

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
            else { return }

            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
