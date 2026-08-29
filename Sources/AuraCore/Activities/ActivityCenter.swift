import SwiftUI

/// Очередь активностей: приоритеты, вытеснение, авто-истечение.
@MainActor
final class ActivityCenter: ObservableObject {
    /// То, что видно в вырезе, — уже с учётом предела.
    @Published private(set) var activities: [Activity] = []
    /// Всё, что есть на самом деле.
    ///
    /// Держать только видимое нельзя: вытесненная активность исчезала
    /// насовсем, и следующее добавление считало очередь короткой снова —
    /// счётчик «ещё N» обнулялся, а чат пропадал молча.
    private var all: [Activity] = []

    /// Больше не влезает в компактный вид осмысленно — остальные видны
    /// в раскрытой панели.
    private let maxVisible = 5
    private var expiryTimer: Timer?

    /// Активность, которую показывает свёрнутый вырез.
    var featured: Activity? { activities.first }

    /// Сколько активностей не видно в свёрнутом вырезе: и те, что стоят
    /// в очереди за первой, и те, что не поместились вовсе. Без вытесненных
    /// значок обещал «+3», когда ждало шесть.
    var hiddenCount: Int { max(0, activities.count - 1) + overflow }

    /// Сколько активностей не поместилось. Показывается строкой «ещё N»:
    /// вытеснять молча нельзя — человек не узнает, что чат вообще был.
    @Published private(set) var overflow = 0

    func start() {
        updateExpiryTimer()
    }

    func stop() {
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    /// Таймер истечения нужен только тогда, когда есть чему истекать.
    ///
    /// Раньше он тикал дважды в секунду всё время работы приложения —
    /// и в покое, когда в вырезе нет вообще ничего. Просыпаться сто семьдесят
    /// тысяч раз в сутки, чтобы отфильтровать пустой список, незачем.
    private func updateExpiryTimer() {
        let needed = all.contains { $0.expiresAt != nil }

        guard needed else {
            expiryTimer?.invalidate()
            expiryTimer = nil
            return
        }
        guard expiryTimer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purgeExpired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
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
        if let existing = all.first(where: { $0.id == activity.id }) {
            next.createdAt = existing.createdAt   // обновление не двигает её в конец очереди
        }

        var list = all.filter { $0.id != activity.id }
        list.append(next)
        apply(list)
    }

    /// Подменить картинку у уже показанной активности.
    ///
    /// Значок уведомления с телефона приезжает позже самого уведомления:
    /// его сначала нужно снять с баннера. Пересобирать активность целиком
    /// нельзя — она уедет в конец очереди и мигнёт.
    func updateArtwork(id: String, artwork: NSImage) {
        if let index = all.firstIndex(where: { $0.id == id }) {
            all[index].artwork = artwork
        }
        // Видимый список — отдельный: активность может лежать в полном
        // и не попасть в него, и наоборот индекс в них не совпадает.
        if let index = activities.firstIndex(where: { $0.id == id }) {
            activities[index].artwork = artwork
        }
    }

    func remove(id: String) {
        remove(id: id, forgetDismissal: true)
    }

    private func remove(id: String, forgetDismissal: Bool) {
        // Провайдер убрал активность сам — значит, повода прятать её больше
        // нет: следующая с тем же именем будет уже про другое.
        if forgetDismissal { dismissed.remove(id) }
        guard all.contains(where: { $0.id == id }) else { return }
        apply(all.filter { $0.id != id })
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
        let alive = all.filter { !$0.isExpired }
        guard alive.count != all.count else { return }
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
            // Одно место оставляем под строку «ещё N»: вытесненные
            // активности исчезали молча, и чат, который не влез,
            // пропадал совсем.
            trimmed = critical + rest.prefix(max(0, maxVisible - 1 - critical.count))
        } else {
            trimmed = sorted
        }
        all = sorted
        overflow = max(0, sorted.count - trimmed.count)

        // Без этой проверки любой повторный upsert запускает пружинную
        // анимацию и перерисовку всего выреза — на ровном месте.
        guard !Self.looksSame(trimmed, activities) else {
            activities = trimmed
            updateExpiryTimer()
            return
        }

        // Та же пружина, что у острова: две разные кривые на одном движении
        // читаются как дрожание.
        withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
            activities = trimmed
        }
        updateExpiryTimer()
    }
}
