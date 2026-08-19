import EventKit
import SwiftUI

/// Ближайшая встреча из Календаря с обратным отсчётом.
///
/// Из всех источников этот замечаешь чаще прочих: до встречи десять минут —
/// и это видно, не открывая ничего.
@MainActor
final class CalendarActivityProvider {
    private let center: ActivityCenter
    private let store = EKEventStore()
    private var timer: Timer?
    private var hasAccess = false

    private let activityID = "calendar.next"
    /// За сколько до начала показывать встречу.
    private let lookahead: TimeInterval = 30 * 60

    init(center: ActivityCenter) {
        self.center = center
    }

    var isAvailable: Bool { hasAccess }

    func start() {
        stop()

        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.hasAccess = granted
                    guard granted else {
                        NSLog("Aura: доступ к календарю не выдан")
                        return
                    }
                    self.beginPolling()
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        center.remove(id: activityID)
    }

    private func beginPolling() {
        check()
        // Раз в полминуты: чаще незачем, отсчёт всё равно идёт минутами.
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func check() {
        guard let event = nextEvent() else {
            center.remove(id: activityID)
            return
        }

        let minutes = Int(event.startDate.timeIntervalSinceNow / 60)
        // Идущая встреча — тоже событие: показываем, что она уже началась.
        let isRunning = event.startDate <= Date()

        center.upsert(
            Activity(
                id: activityID,
                title: event.title ?? "Встреча",
                subtitle: isRunning ? "идёт сейчас" : Self.countdown(minutes: minutes),
                symbol: "calendar",
                tint: .orange,
                priority: minutes <= 5 && !isRunning ? .important : .normal,
                indicator: isRunning ? .none : .text("\(max(0, minutes))м")
            )
        )
    }

    private func nextEvent() -> EKEvent? {
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-15 * 60),
            end: now.addingTimeInterval(lookahead),
            calendars: nil
        )

        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .min { $0.startDate < $1.startDate }
    }

    nonisolated static func countdown(minutes: Int) -> String {
        switch minutes {
        case ..<0: "вот-вот"
        case 0: "меньше минуты"
        case 1: "через минуту"
        case 2...4: "через \(minutes) минуты"
        default: "через \(minutes) минут"
        }
    }
}
