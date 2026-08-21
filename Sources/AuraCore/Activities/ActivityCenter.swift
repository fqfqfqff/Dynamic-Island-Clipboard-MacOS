import SwiftUI

/// Очередь активностей: приоритеты, вытеснение, авто-истечение.
@MainActor
final class ActivityCenter: ObservableObject {
    @Published private(set) var activities: [Activity] = []

    /// Больше не влезает в компактный вид осмысленно — остальные видны
    /// в раскрытой панели.
    private let maxVisible = 5
    private var expiryTimer: Timer?

    /// Активность, которую показывает свёрнутый вырез.
    var featured: Activity? { activities.first }

    var hiddenCount: Int { max(0, activities.count - 1) }

    func start() {
        stop()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purgeExpired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    func stop() {
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    /// Активности, которые пользователь убрал руками.
    ///
    /// Без этого списка убрать нечего: провайдер поставит своё обратно на
    /// следующем же опросе. Запись живёт, пока провайдер не уберёт активность
    /// сам, — то есть пока загрузка не кончится или уведомление не сменится.
    private var dismissed: Set<String> = []

    /// Убрать по воле пользователя — и не возвращать.
    func dismiss(id: String) {
        dismissed.insert(id)
        remove(id: id, forgetDismissal: false)
    }

    func upsert(_ activity: Activity) {
        guard !dismissed.contains(activity.id) else { return }
        var next = activity
        if let existing = activities.first(where: { $0.id == activity.id }) {
            next.createdAt = existing.createdAt   // обновление не двигает её в конец очереди
        }

        var list = activities.filter { $0.id != activity.id }
        list.append(next)
        apply(list)
    }

    func remove(id: String) {
        remove(id: id, forgetDismissal: true)
    }

    private func remove(id: String, forgetDismissal: Bool) {
        // Провайдер убрал активность сам — значит, повода прятать её больше
        // нет: следующая с тем же именем будет уже про другое.
        if forgetDismissal { dismissed.remove(id) }
        guard activities.contains(where: { $0.id == id }) else { return }
        apply(activities.filter { $0.id != id })
    }

    func removeAll() {
        dismissed.removeAll()
        apply([])
    }

    private static func looksSame(_ lhs: [Activity], _ rhs: [Activity]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.id == right.id
                && left.title == right.title
                && left.subtitle == right.subtitle
                && left.symbol == right.symbol
                && left.priority == right.priority
        }
    }

    private func purgeExpired() {
        let alive = activities.filter { !$0.isExpired }
        guard alive.count != activities.count else { return }
        apply(alive)
    }

    /// Сортировка и вытеснение. Критичные не выкидываем никогда — они и есть
    /// причина, по которой пользователь смотрит на вырез.
    private func apply(_ list: [Activity]) {
        let sorted = list.sorted { lhs, rhs in
            lhs.priority != rhs.priority
                ? lhs.priority > rhs.priority
                : lhs.createdAt > rhs.createdAt
        }

        let trimmed: [Activity]
        if sorted.count > maxVisible {
            let critical = sorted.filter { $0.priority == .critical }
            let rest = sorted.filter { $0.priority != .critical }
            trimmed = critical + rest.prefix(max(0, maxVisible - critical.count))
        } else {
            trimmed = sorted
        }

        // Без этой проверки любой повторный upsert запускает пружинную
        // анимацию и перерисовку всего выреза — на ровном месте.
        guard !Self.looksSame(trimmed, activities) else {
            activities = trimmed
            return
        }

        withAnimation(.smooth(duration: 0.4, extraBounce: 0.1)) {
            activities = trimmed
        }
    }
}
