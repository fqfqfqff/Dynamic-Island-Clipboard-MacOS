import AppKit
import SwiftUI

/// Отдельное окно истории буфера — по ⌥⌘V или по клику на иконку в строке меню.
///
/// Панель не активирующая: приложение, в котором работает пользователь,
/// остаётся активным, и вставлять можно прямо в него.
@MainActor
final class ClipboardWindowController {
    private var panel: NSPanel?
    private var outsideClickMonitors: [Any] = []
    private let clipboard: ClipboardService
    private let settings: SettingsStore

    private static let size = CGSize(width: 640, height: 380)

    init(clipboard: ClipboardService, settings: SettingsStore) {
        self.clipboard = clipboard
        self.settings = settings
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // Открываем у того экрана, где сейчас курсор.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(CGPoint(
                x: frame.midX - Self.size.width / 2,
                y: frame.midY - Self.size.height / 2
            ))
        }

        panel.makeKeyAndOrderFront(nil)
        watchOutsideClicks()
    }

    func hide() {
        panel?.orderOut(nil)
        stopWatchingOutsideClicks()
    }

    /// Клик мимо окна закрывает историю — как это делает любая всплывающая
    /// панель в системе.
    private func watchOutsideClicks() {
        guard outsideClickMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        // Глобальный монитор ловит клики в чужих приложениях; события внутри
        // Aura до него не доходят, поэтому клик по самой истории её не закроет.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        } {
            outsideClickMonitors.append(global)
        }

        // Локальный нужен для остальных окон Aura — например, настроек.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel { self.hide() }
            }
            return event
        } {
            outsideClickMonitors.append(local)
        }
    }

    private func stopWatchingOutsideClicks() {
        outsideClickMonitors.forEach(NSEvent.removeMonitor)
        outsideClickMonitors.removeAll()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .closable],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        panel.contentView = NSHostingView(
            rootView: ClipboardWindowView(
                onUse: { [weak self] item in self?.use(item) },
                onClose: { [weak self] in self?.hide() }
            )
            .environmentObject(clipboard)
            .environmentObject(settings)
        )
        return panel
    }

    private func use(_ item: ClipboardItem) {
        clipboard.copyToPasteboard(item)
        hide()

        guard settings.autoPaste else { return }
        guard Paster.canPaste else {
            // Без разрешения ⌘V отправить нельзя. Настройки открываем один раз
            // за запуск: дальше об этом говорит баннер в самом окне.
            guard !settings.didAskAccessibility else { return }
            settings.didAskAccessibility = true
            Permissions.requestAccessibility()
            Permissions.openAccessibilitySettings()
            return
        }
        Paster.pasteIntoFrontmostApp()
    }
}
