import AppKit

/// Сколько времени пользователь не трогал мышь и клавиатуру.
///
/// На этом строится витрина «вместо экрана блокировки»: пока человек отошёл,
/// экран показывает плеер с часами, а не гаснет.
@MainActor
final class IdleWatcher {
    var onIdle: (() -> Void)?
    var onActive: (() -> Void)?

    /// Порог простоя в секундах.
    var threshold: TimeInterval = 180

    private var timer: Timer?
    private var wasIdle = false

    func start() {
        stop()
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        wasIdle = false
    }

    private func check() {
        let idle = Self.secondsSinceLastInput()

        if !wasIdle, idle >= threshold {
            wasIdle = true
            onIdle?()
        } else if wasIdle, idle < 5 {
            wasIdle = false
            onActive?()
        }
    }

    static func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
    }
}
