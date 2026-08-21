import AppKit

/// Следит за зажатой ⌥ — по ней остров показывает подробности.
///
/// Мониторы клавиш-модификаторов, в отличие от обычных клавиатурных,
/// разрешения Универсального доступа не требуют: `flagsChanged` доступен
/// всем. Событий здесь единицы в минуту, поэтому наблюдение бесплатное.
@MainActor
final class ModifierWatcher: ObservableObject {
    @Published private(set) var isOptionDown = false

    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }

        let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.apply(event.modifierFlags) }
        }
        // Локальный нужен отдельно: пока курсор над нашей панелью, глобальный
        // монитор событий не получает.
        let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.apply(event.modifierFlags) }
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        isOptionDown = false
    }

    private func apply(_ flags: NSEvent.ModifierFlags) {
        let down = flags.contains(.option)
        guard down != isOptionDown else { return }
        isOptionDown = down
    }
}
