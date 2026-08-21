import Network
import SwiftUI

/// Показывает в вырезе, куда подключён Mac: обычная сеть, кабель или телефон
/// в режиме модема.
///
/// Работает через `NWPathMonitor` — события, а не опрос: пока сеть не
/// меняется, провайдер не стоит ничего. Имя сети здесь намеренно не читается:
/// SSID закрыт службами геолокации, а ради строчки в вырезе просить у
/// пользователя доступ к местоположению — плохой обмен.
///
/// Режим модема определяется признаком «дорогого» подключения: Network.framework
/// помечает им и раздачу по Wi-Fi, и телефон, подключённый кабелем.
@MainActor
final class NetworkActivityProvider {
    struct Snapshot: Equatable {
        enum Link: Equatable {
            case offline
            case wifi
            case ethernet
            /// Телефон раздаёт интернет — по Wi-Fi или кабелем.
            case hotspot
            case other
        }

        var link: Link
        /// Режим экономии трафика включён на стороне сети.
        var isConstrained: Bool
    }

    private let center: ActivityCenter
    private var monitor: NWPathMonitor?
    private var previous: Snapshot?

    private let changeActivityID = "network.change"
    private let offlineActivityID = "network.offline"
    private let hotspotActivityID = "network.hotspot"

    init(center: ActivityCenter) {
        self.center = center
    }

    func start() {
        guard monitor == nil else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            // Колбэк приходит со своей очереди; разбор пути от изоляции
            // свободен, на главный поток уходит уже готовый снимок.
            let snapshot = Self.snapshot(from: path)
            Task { @MainActor in self?.apply(snapshot) }
        }
        monitor.start(queue: DispatchQueue(label: "dev.kekch.aura.network", qos: .utility))
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        previous = nil
        center.remove(id: changeActivityID)
        center.remove(id: offlineActivityID)
        center.remove(id: hotspotActivityID)
    }

    // MARK: - Разбор пути

    nonisolated static func snapshot(from path: NWPath) -> Snapshot {
        guard path.status == .satisfied else {
            return Snapshot(link: .offline, isConstrained: false)
        }
        // Признак «дорогого» подключения выставляет сама система, и выставляет
        // его именно раздаче с телефона — по нему режим модема и виден.
        if path.isExpensive {
            return Snapshot(link: .hotspot, isConstrained: path.isConstrained)
        }
        if path.usesInterfaceType(.wifi) {
            return Snapshot(link: .wifi, isConstrained: path.isConstrained)
        }
        if path.usesInterfaceType(.wiredEthernet) {
            return Snapshot(link: .ethernet, isConstrained: path.isConstrained)
        }
        return Snapshot(link: .other, isConstrained: path.isConstrained)
    }

    // MARK: - Показ

    private func apply(_ snapshot: Snapshot) {
        guard snapshot != previous else { return }
        let hadPrevious = previous != nil
        previous = snapshot

        // Пропажа сети — не событие на четыре секунды: пока связи нет,
        // это состояние, и оно должно быть видно.
        if snapshot.link == .offline {
            center.remove(id: hotspotActivityID)
            center.upsert(
                Activity(
                    id: offlineActivityID,
                    title: t("ui.a1c30f4b", "Нет сети"),
                    subtitle: t("ui.6c2f8d51", "Подключение потеряно"),
                    symbol: "wifi.slash",
                    tint: .orange,
                    priority: .important
                )
            )
            return
        }
        center.remove(id: offlineActivityID)

        // Режим модема висит, пока не отключатся: трафик считает телефон,
        // и знать об этом полезно всё время, а не четыре секунды.
        if snapshot.link == .hotspot {
            center.upsert(
                Activity(
                    id: hotspotActivityID,
                    title: t("ui.7d4e9a02", "Режим модема"),
                    subtitle: snapshot.isConstrained
                        ? t("ui.3b8c17ef", "Экономия трафика")
                        : t("ui.9f21ab6d", "Интернет с телефона"),
                    symbol: "personalhotspot",
                    tint: .green,
                    priority: .normal
                )
            )
            return
        }
        center.remove(id: hotspotActivityID)

        // Первый снимок приходит сразу после запуска — показывать «подключено»
        // на старте приложения незачем, это не событие.
        guard hadPrevious else { return }

        center.upsert(
            Activity(
                id: changeActivityID,
                title: title(for: snapshot.link),
                subtitle: t("ui.5e6b0c73", "Сеть доступна"),
                symbol: symbol(for: snapshot.link),
                tint: .blue,
                priority: .normal,
                expiresAt: Date().addingTimeInterval(4)
            )
        )
    }

    private func title(for link: Snapshot.Link) -> String {
        switch link {
        case .wifi: t("ui.2c9d4e18", "Wi-Fi подключён")
        case .ethernet: t("ui.8a70b3c5", "Кабель подключён")
        default: t("ui.5e6b0c73", "Сеть доступна")
        }
    }

    private func symbol(for link: Snapshot.Link) -> String {
        switch link {
        case .wifi: "wifi"
        case .ethernet: "cable.connector"
        case .hotspot: "personalhotspot"
        default: "network"
        }
    }
}
