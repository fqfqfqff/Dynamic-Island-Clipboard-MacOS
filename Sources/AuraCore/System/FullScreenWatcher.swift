import AppKit

/// Следит, не занял ли экран полноэкранный режим.
///
/// Панель Aura висит поверх строки меню, и в полноэкранном видео это мешает:
/// система держит верхнюю кромку «живой» и показывает кнопки управления окном.
///
/// Признака два, потому что по отдельности каждый ошибается:
/// - скрытая строка меню — дёшево и мгновенно, но так же выглядит режим
///   автоскрытия меню;
/// - окно на весь экран — надёжно, но требует обхода списка окон, поэтому
///   проверяется реже.
@MainActor
final class FullScreenWatcher {
    var onChange: ((Bool) -> Void)?

    private var deepTimer: Timer?
    private var spaceObserver: NSObjectProtocol?

    private var isFullScreen = false
    private var deepResult = false
    private var screenProvider: () -> NSScreen? = { nil }

    func start(screen: @escaping () -> NSScreen?) {
        stop()
        screenProvider = screen
        deepCheck()
        check()

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.deepCheck()
                self?.check()
            }
        }

        deepTimer = schedule(every: 4) { [weak self] in
            self?.deepCheck()
            self?.check()
        }
    }

    func stop() {
        deepTimer?.invalidate()
        deepTimer = nil
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        spaceObserver = nil
    }

    /// Дешёвая проверка — вызывается ещё и на движение мыши.
    func check() {
        guard let screen = screenProvider() else { return }

        let menuBarHidden = screen.visibleFrame.maxY >= screen.frame.maxY - 1
        let next = menuBarHidden || deepResult

        guard next != isFullScreen else { return }
        isFullScreen = next
        onChange?(next)
    }

    /// Есть ли обычное окно приложения, накрывающее экран целиком.
    private func deepCheck() {
        guard let screen = screenProvider() else { return }
        let frame = screen.frame

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return }

        deepResult = windows.contains { window in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let owner = window[kCGWindowOwnerName as String] as? String, owner != "Aura",
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"]
            else { return false }

            return width >= frame.width - 2 && height >= frame.height - 2
        }
    }

    private func schedule(every interval: TimeInterval, action: @escaping () -> Void) -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
