import AppKit

/// Спит ли экран и активна ли сессия пользователя.
///
/// Когда экран погашен или пользователь переключился в другую сессию, всё
/// оформление вырезано из поля зрения — держать в это время анализ звука,
/// таймеры и опросы плеера бессмысленно.
@MainActor
final class ScreenStateWatcher {
    var onChange: ((Bool) -> Void)?

    /// true — экран виден пользователю.
    private(set) var isVisible = true

    private var observers: [NSObjectProtocol] = []

    func start() {
        stop()
        let center = NSWorkspace.shared.notificationCenter

        let asleep = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        let awake = [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]

        for name in asleep {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(visible: false) }
            })
        }
        for name in awake {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(visible: true) }
            })
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    private func update(visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        onChange?(visible)
    }
}
