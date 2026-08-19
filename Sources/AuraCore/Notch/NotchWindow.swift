import AppKit
import SwiftUI

/// Панель, висящая поверх строки меню.
///
/// `.nonactivatingPanel` — чтобы клик по вырезу не переводил фокус на Aura и не
/// выбивал пользователя из приложения, в котором он работает.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar + 1          // выше строки меню, иначе вырез перекроет нас
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        // Без .fullScreenAuxiliary: панель намеренно не показывается поверх
        // полноэкранных приложений, чтобы не мешать видео и играм.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }
}

/// Пропускает мышь насквозь везде, кроме текущей видимой формы панели.
final class NotchContainerView: NSView {
    var interactiveRect: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRect().contains(point) else { return nil }
        return super.hitTest(point)
    }
}
