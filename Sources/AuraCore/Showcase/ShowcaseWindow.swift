import AppKit
import SwiftUI

/// Витрина: плеер во весь экран с часами.
///
/// Так решается задача «видеть, что играет, не подходя к клавиатуре».
/// Рисовать на самом экране блокировки macOS сторонним приложениям не даёт —
/// при блокировке сессия пользователя скрывается целиком. Витрина занимает
/// экран до блокировки и удерживает дисплей от засыпания, давая тот же
/// результат: подошёл, посмотрел, отошёл.
@MainActor
final class ShowcaseWindowController {
    private var window: NSWindow?
    private let media: NowPlayingProvider
    private let lyrics: LyricsProvider
    private let settings: SettingsStore
    private let power = PowerAssertion()

    init(media: NowPlayingProvider, lyrics: LyricsProvider, settings: SettingsStore) {
        self.media = media
        self.lyrics = lyrics
        self.settings = settings
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// Живёт ли сейчас окно вместе со всем деревом видов внутри.
    ///
    /// Нужно тесту: скрытое окно продолжает работать целиком, и это стоило
    /// приложению вдесятеро большего расхода в покое.
    var hasWindow: Bool { window != nil }

    func show() {
        // Без экрана показывать витрину негде.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let window = self.window ?? makeWindow(on: screen)
        self.window = window

        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        power.hold(reason: "Aura: витрина плеера")
    }

    func hide() {
        window?.orderOut(nil)
        // Скрытое окно продолжает жить, и SwiftUI внутри него исправно
        // тикает: строка песни раз в треть секунды, полоса времени раз
        // в четверть, часы раз в секунду. Смотреть на это некому, а расход
        // остаётся навсегда — витрину достаточно открыть один раз за сеанс.
        //
        // Снимаем содержимое и отпускаем окно: `show` соберёт заново.
        window?.contentView = nil
        window = nil
        power.release()
    }

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Уровень экранной заставки: витрина перекрывает всё, включая Dock и
        // строку меню, но при блокировке экрана система всё равно спрячет её.
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(
            rootView: ShowcaseView(onClose: { [weak self] in self?.hide() })
                .environmentObject(media)
                .environmentObject(lyrics)
                .environmentObject(settings)
        )
        return window
    }
}
