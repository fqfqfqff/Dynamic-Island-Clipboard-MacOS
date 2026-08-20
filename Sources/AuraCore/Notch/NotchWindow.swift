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

/// Пропускает мышь насквозь везде, кроме текущей видимой формы панели,
/// и принимает файлы, которые бросают на вырез.
final class NotchContainerView: NSView {
    var interactiveRect: () -> CGRect = { .zero }
    var onDragEnter: (() -> Void)?
    var onDragExit: (() -> Void)?
    var onDrop: (([URL]) -> Void)?
    /// Вертикальная прокрутка над вырезом — громкость, горизонтальная — трек.
    var onScrollVertical: ((CGFloat) -> Void)?
    var onScrollHorizontal: ((CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRect().contains(point) else { return nil }
        return super.hitTest(point)
    }

    // MARK: - Прокрутка

    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard interactiveRect().contains(point) else {
            super.scrollWheel(with: event)
            return
        }

        // Что это было — вертикальный жест или горизонтальный — решаем
        // по преобладающей оси: на трекпаде чистых движений не бывает.
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5 {
            onScrollHorizontal?(event.scrollingDeltaX)
        } else {
            onScrollVertical?(event.scrollingDeltaY)
        }
    }

    // MARK: - Приём файлов

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !urls(from: sender).isEmpty else { return [] }
        onDragEnter?()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExit?()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !urls(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = urls(from: sender)
        guard !files.isEmpty else { return false }
        onDrop?(files)
        return true
    }

    private func urls(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }
}
