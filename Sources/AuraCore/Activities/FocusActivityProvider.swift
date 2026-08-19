import AppKit
import SwiftUI

/// Режим фокусирования: «Не беспокоить», «Работа», «Сон» и прочие.
///
/// Публичного API для этого в macOS нет. Состояние лежит в файле
/// `~/Library/DoNotDisturb/DB/Assertions.json`, и он закрыт TCC: без полного
/// доступа к диску чтение вернёт отказ. Поэтому провайдер тихо выключается,
/// если файла не видно, — вместо того чтобы притворяться, что фокус выключен.
@MainActor
final class FocusActivityProvider {
    private let center: ActivityCenter
    private var timer: Timer?
    private var currentMode: String?
    private let activityID = "system.focus"

    private var assertionsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    }

    private var configurationsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/ModeConfigurations.json")
    }

    init(center: ActivityCenter) {
        self.center = center
    }

    /// Есть ли у нас доступ к состоянию фокуса.
    var isAvailable: Bool {
        (try? Data(contentsOf: assertionsURL)) != nil
    }

    func start() {
        stop()
        guard isAvailable else {
            NSLog("Aura: режим фокусирования недоступен — нужен полный доступ к диску")
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        currentMode = readMode()   // стартовое состояние не показываем
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        center.remove(id: activityID)
        currentMode = nil
    }

    private func check() {
        let mode = readMode()
        guard mode != currentMode else { return }
        currentMode = mode

        guard let mode else {
            center.upsert(
                Activity(
                    id: activityID,
                    title: "Фокусирование выключено",
                    symbol: "moon.slash",
                    tint: .gray,
                    priority: .normal,
                    expiresAt: Date().addingTimeInterval(4)
                )
            )
            return
        }

        center.upsert(
            Activity(
                id: activityID,
                title: Self.humanName(for: mode),
                subtitle: "Режим фокусирования",
                symbol: Self.symbol(for: mode),
                tint: .purple,
                priority: .normal,
                expiresAt: Date().addingTimeInterval(5)
            )
        )
    }

    /// Идентификатор включённого режима или nil, если фокус выключен.
    private func readMode() -> String? {
        guard let data = try? Data(contentsOf: assertionsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let records = json["storeAssertionRecords"] as? [[String: Any]] ?? []
        for record in records {
            guard let details = record["assertionDetails"] as? [String: Any],
                  let identifier = details["assertionDetailsModeIdentifier"] as? String
            else { continue }
            return identifier
        }
        return nil
    }

    nonisolated static func humanName(for identifier: String) -> String {
        // Системные режимы приходят обратными доменными именами.
        let known: [String: String] = [
            "com.apple.donotdisturb.mode.default": "Не беспокоить",
            "com.apple.sleep.sleep-mode": "Сон",
            "com.apple.focus.work": "Работа",
            "com.apple.focus.personal": "Личное",
            "com.apple.focus.mindfulness": "Осознанность",
            "com.apple.focus.reading": "Чтение",
            "com.apple.focus.fitness": "Тренировка",
            "com.apple.focus.gaming": "Игра",
            "com.apple.focus.driving": "За рулём",
        ]
        if let name = known[identifier] { return name }

        // Пользовательский режим: идентификатор вида "…mode.UUID" читать нечего.
        return "Фокусирование"
    }

    nonisolated static func symbol(for identifier: String) -> String {
        switch identifier {
        case let id where id.contains("sleep"): "bed.double.fill"
        case let id where id.contains("work"): "briefcase.fill"
        case let id where id.contains("personal"): "person.fill"
        case let id where id.contains("reading"): "book.fill"
        case let id where id.contains("fitness"): "figure.run"
        case let id where id.contains("gaming"): "gamecontroller.fill"
        case let id where id.contains("driving"): "car.fill"
        default: "moon.fill"
        }
    }
}
