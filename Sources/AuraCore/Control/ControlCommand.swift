import SwiftUI

/// Полезная нагрузка для внешней активности: ровно то, что стороннее
/// приложение или скрипт может показать в вырезе.
struct ActivityPayload: Decodable {
    var id: String
    var title: String
    var subtitle: String?
    var symbol: String?
    var tint: String?
    var progress: Double?
    var text: String?
    var pulse: Bool?
    /// Через сколько секунд активность исчезнет сама.
    var ttl: Double?
    var priority: String?

    func makeActivity() -> Activity {
        let indicator: Activity.Indicator
        if let progress {
            indicator = .progress(progress)
        } else if let text {
            indicator = .text(text)
        } else if pulse == true {
            indicator = .pulse
        } else {
            indicator = .none
        }

        return Activity(
            id: "external.\(id)",
            title: title,
            subtitle: subtitle,
            symbol: symbol ?? "app.dashed",
            tint: Self.color(named: tint),
            priority: Self.priority(named: priority),
            indicator: indicator,
            expiresAt: ttl.map { Date().addingTimeInterval($0) }
        )
    }

    private static func color(named name: String?) -> Color {
        switch name?.lowercased() {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "cyan": .cyan
        case "blue": .blue
        case "purple": .purple
        case "pink": .pink
        case "gray", "grey": .gray
        default: .white
        }
    }

    private static func priority(named name: String?) -> Activity.Priority {
        switch name?.lowercased() {
        case "ambient": .ambient
        case "important": .important
        case "critical": .critical
        default: .normal
        }
    }
}

enum ControlCommand {
    case push(ActivityPayload)
    case remove(id: String)
    case list
    case open
    case close
    case ping
    case status
    case showcase(Bool)
    case autostart(Bool)
    /// Снять все непрочитанные уведомления разом.
    case clearNotifications
    /// Снимок правого верхнего угла экрана — того места, где система
    /// показывает баннеры. Нужен для разбора: без него не отличить
    /// «зеркало не работает» от «баннера не было».
    /// Таймер в вырезе: минуты или nil, чтобы остановить.
    case timer(Double?)
    case bannerShot
    /// Снимок всего экрана — чтобы посмотреть на окна приложения снаружи.
    case screenShot
    /// Открыть окно настроек.
    case openSettings
    /// Открыть журнал уведомлений.
    case openHistory

    private struct Envelope: Decodable {
        let cmd: String
        let id: String?
        /// Минуты для таймера.
        let minutes: Double?
    }

    static func parse(json data: Data) throws -> ControlCommand {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(Envelope.self, from: data)

        switch envelope.cmd {
        case "activity.push":
            return .push(try decoder.decode(ActivityPayload.self, from: data))
        case "activity.remove":
            guard let id = envelope.id else { throw ControlError.missingField("id") }
            return .remove(id: id)
        case "activity.list":
            return .list
        case "notch.open":
            return .open
        case "notch.close":
            return .close
        case "ping":
            return .ping
        case "status":
            return .status
        case "notifications.clear":
            return .clearNotifications
        case "banner.shot":
            return .bannerShot
        case "timer.start":
            return .timer(envelope.minutes ?? 5)
        case "timer.stop":
            return .timer(nil)
        case "screen.shot":
            return .screenShot
        case "settings.open":
            return .openSettings
        case "history.open":
            return .openHistory
        case "showcase.open":
            return .showcase(true)
        case "showcase.close":
            return .showcase(false)
        case "autostart.on":
            return .autostart(true)
        case "autostart.off":
            return .autostart(false)
        default:
            throw ControlError.unknownCommand(envelope.cmd)
        }
    }

    /// Разбор `aura://activity/push?id=build&title=Сборка&progress=0.4`.
    static func parse(url: URL) throws -> ControlCommand {
        let action = [url.host, url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: ".")

        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]

        switch action {
        case "activity.push":
            guard let id = query["id"], let title = query["title"] else {
                throw ControlError.missingField("id и title")
            }
            return .push(ActivityPayload(
                id: id,
                title: title,
                subtitle: query["subtitle"],
                symbol: query["symbol"],
                tint: query["tint"],
                progress: query["progress"].flatMap(Double.init),
                text: query["text"],
                pulse: query["pulse"] == "1" || query["pulse"] == "true",
                ttl: query["ttl"].flatMap(Double.init),
                priority: query["priority"]
            ))
        case "activity.remove":
            guard let id = query["id"] else { throw ControlError.missingField("id") }
            return .remove(id: id)
        case "notch.open":
            return .open
        case "notch.close":
            return .close
        case "status":
            return .status
        case "notifications.clear":
            return .clearNotifications
        case "banner.shot":
            return .bannerShot
        case "timer.stop":
            return .timer(nil)
        case "screen.shot":
            return .screenShot
        case "settings.open":
            return .openSettings
        case "history.open":
            return .openHistory
        case "showcase.open":
            return .showcase(true)
        case "showcase.close":
            return .showcase(false)
        case "autostart.on":
            return .autostart(true)
        case "autostart.off":
            return .autostart(false)
        default:
            throw ControlError.unknownCommand(action)
        }
    }
}

enum ControlError: LocalizedError {
    case unknownCommand(String)
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let name): "неизвестная команда: \(name)"
        case .missingField(let name): "не хватает поля: \(name)"
        }
    }
}
