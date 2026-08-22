import IOKit.ps
import SwiftUI

struct BatterySnapshot: Equatable {
    let percent: Int
    let isCharging: Bool
    let isPluggedIn: Bool
}

enum BatteryReader {
    static func read() -> BatterySnapshot? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            guard let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int,
                  max > 0 else { continue }

            let state = description[kIOPSPowerSourceStateKey] as? String
            let isPluggedIn = state == kIOPSACPowerValue
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false

            return BatterySnapshot(
                percent: Int(round(Double(current) / Double(max) * 100)),
                isCharging: isCharging,
                isPluggedIn: isPluggedIn
            )
        }
        return nil
    }
}

/// Показывает зарядку в вырезе: короткая карточка при подключении кабеля и
/// постоянная — когда заряд на исходе.
@MainActor
final class BatteryActivityProvider {
    private let center: ActivityCenter
    private var timer: Timer?
    private var previous: BatterySnapshot?

    private let powerActivityID = "battery.power"
    private let lowActivityID = "battery.low"
    private let lowThreshold = 20

    init(center: ActivityCenter) {
        self.center = center
    }

    func start() {
        stop()
        tick()
        let timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let snapshot = BatteryReader.read() else { return }
        defer { previous = snapshot }

        // Кабель воткнули или выдернули — короткая карточка на несколько секунд.
        if let previous, previous.isPluggedIn != snapshot.isPluggedIn {
            center.upsert(
                Activity(
                    id: powerActivityID,
                    title: snapshot.isPluggedIn ? "Питание подключено" : "Работа от батареи",
                    subtitle: snapshot.isCharging ? "Заряжается" : nil,
                    symbol: snapshot.isPluggedIn ? "bolt.fill" : "battery.50",
                    tint: snapshot.isPluggedIn ? .green : .orange,
                    priority: .normal,
                    indicator: .text("\(snapshot.percent)%"),
                    expiresAt: Date().addingTimeInterval(5)
                )
            )
        }

        if snapshot.percent <= lowThreshold && !snapshot.isPluggedIn {
            center.upsert(
                Activity(
                    id: lowActivityID,
                    title: "Заряд \(snapshot.percent)%",
                    subtitle: t("ui.6f21a904", "Пора к розетке"),
                    symbol: "battery.25",
                    tint: .red,
                    priority: .critical,
                    indicator: .progress(Double(snapshot.percent) / 100)
                )
            )
        } else {
            center.remove(id: lowActivityID)
        }
    }
}
