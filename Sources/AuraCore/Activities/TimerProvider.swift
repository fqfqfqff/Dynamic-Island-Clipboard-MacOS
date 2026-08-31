import AppKit
import SwiftUI

/// Таймер в вырезе.
///
/// В macOS таймера нет вовсе: есть будильники в «Часах», которые живут
/// в отдельном окне и напоминают о себе баннером. А таймер — это то, на что
/// смотрят краем глаза: сколько осталось до конца чайника, перерыва, помидора.
/// Вырез для этого и создан.
@MainActor
final class TimerProvider: ObservableObject {
    private let center: ActivityCenter

    private var timer: Timer?
    private var endsAt: Date?
    private var total: TimeInterval = 0
    private var label: String?

    private let activityID = "timer.running"
    private let doneID = "timer.done"
    private let stopwatchID = "timer.stopwatch"

    /// Секундомер идёт вверх и не заканчивается сам.
    private var startedAt: Date?

    init(center: ActivityCenter) {
        self.center = center
    }

    var isRunning: Bool { endsAt != nil }

    /// Сколько осталось. Нужно и для диагностики, и для меню.
    var remaining: TimeInterval {
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSinceNow)
    }

    func start(minutes: Double, label: String? = nil) {
        start(seconds: minutes * 60, label: label)
    }

    func start(seconds: TimeInterval, label: String? = nil) {
        guard seconds > 0 else { return }
        stop()

        total = seconds
        endsAt = Date().addingTimeInterval(seconds)
        self.label = label
        center.remove(id: doneID)
        tick()

        // Секунда — не выбор, а требование: цифры на вырезе идут по секундам.
        // Зато таймер и живёт ровно столько, сколько идёт.
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Секундомер: то же движение, но вверх и без конца.
    ///
    /// Отдельная кнопка, а не режим таймера: их путают в любом приложении,
    /// где они живут в одном месте, и это единственное, что о них помнят.
    var isCounting: Bool { startedAt != nil }

    func startStopwatch() {
        stop()
        startedAt = Date()
        tick()

        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        endsAt = nil
        startedAt = nil
        center.remove(id: activityID)
        center.remove(id: stopwatchID)
    }

    // MARK: - Ход

    private func tick() {
        if let startedAt {
            center.upsert(
                Activity(
                    id: stopwatchID,
                    title: t("ui.9d2c40b7", "Секундомер"),
                    subtitle: Self.spelled(Date().timeIntervalSince(startedAt)),
                    symbol: "stopwatch",
                    tint: .cyan,
                    priority: .normal,
                    indicator: .text(Self.spelled(Date().timeIntervalSince(startedAt)))
                )
            )
            return
        }

        guard let endsAt else { return }
        let left = max(0, endsAt.timeIntervalSinceNow)

        guard left > 0 else { return finish() }

        center.upsert(
            Activity(
                id: activityID,
                title: label ?? t("ui.a70f2d31", "Таймер"),
                subtitle: Self.spelled(left),
                symbol: "timer",
                tint: .orange,
                priority: .normal,
                // Цифры, а не кольцо: у таймера смысл в том, сколько
                // осталось, и это должно читаться боковым зрением, не
                // требуя оценивать сектор на глаз.
                indicator: .text(Self.spelled(left))
            )
        )
    }

    private func finish() {
        stop()

        center.upsert(
            Activity(
                id: doneID,
                title: label ?? t("ui.a70f2d31", "Таймер"),
                subtitle: t("ui.0c9b7e42", "Время вышло"),
                symbol: "timer",
                tint: .orange,
                priority: .important,
                indicator: .pulse,
                expiresAt: Date().addingTimeInterval(30)
            )
        )

        // Звук системный: свой пришлось бы возить с собой, а этот человек
        // уже знает — им заканчиваются будильники в «Часах».
        NSSound(named: "Glass")?.play()
    }

    /// «5:00», «12:34», «1:02:03» — как на часах, а не «300 с».
    nonisolated static func spelled(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let rest = whole % 60

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}
