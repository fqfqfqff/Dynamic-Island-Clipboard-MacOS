import AppKit

/// Следит за курсором глобально, чтобы вырез реагировал на наведение даже
/// когда Aura неактивна.
///
/// Мониторы мыши, в отличие от клавиатурных, не требуют разрешения Accessibility.
@MainActor
final class MouseTracker {
    /// Точка и скорость курсора в точках за секунду.
    var onMove: ((CGPoint, CGFloat) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Движение мыши приходит сотнями событий в секунду; вырезу столько не нужно.
    private var lastDelivery = Date.distantPast
    private var lastPoint: CGPoint?
    private let minimumInterval: TimeInterval = 1.0 / 20

    func start() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.deliver()
            }
        }

        // Локальный монитор нужен отдельно: пока курсор над нашей же панелью,
        // глобальный монитор событий не получает.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.deliver()
            }
            return event
        }
    }

    private func deliver() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastDelivery)
        guard elapsed >= minimumInterval else { return }

        let point = NSEvent.mouseLocation
        var speed: CGFloat = 0
        if let lastPoint, elapsed > 0, elapsed < 0.5 {
            let distance = hypot(point.x - lastPoint.x, point.y - lastPoint.y)
            speed = distance / CGFloat(elapsed)
        }

        lastDelivery = now
        lastPoint = point
        onMove?(point, speed)
    }

    func stop() {
        [globalMonitor, localMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
    }
}
