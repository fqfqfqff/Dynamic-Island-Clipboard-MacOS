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
    private var watcher: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
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

        // Фокус меняют несколько раз в день, а файл о смене пишется сразу.
        // Слушаем файл, а не опрашиваем его: пять секунд опроса — это 720
        // чтений диска в час ради события, которого обычно нет.
        watch()

        // Файл переписывается целиком, а не правится на месте: система
        // пишет новый и подменяет. Старый дескриптор после этого мёртв,
        // поэтому редкая проверка нужна как страховка и как способ
        // заметить подмену.
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.check()
                self?.rewatchIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        currentMode = readMode()   // стартовое состояние не показываем
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        watcher?.cancel()
        watcher = nil
        descriptor = -1
        center.remove(id: activityID)
        currentMode = nil
    }

    // MARK: - Слежение за файлом

    private func watch() {
        watcher?.cancel()
        watcher = nil
        descriptor = -1

        descriptor = open(assertionsURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let event = self.watcher?.data ?? []
                self.check()

                // Файл подменили — следить больше не за чем, дескриптор
                // указывает на удалённый файл. Открываем заново.
                if event.contains(.delete) || event.contains(.rename) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        MainActor.assumeIsolated {
                            self.watch()
                            self.check()
                        }
                    }
                }
            }
        }
        // Дескриптор захватывается значением, а не читается через `self`.
        // Отмена приходит асинхронно: к моменту, когда обработчик отработает,
        // `self.descriptor` уже может указывать на новое слежение — и тогда
        // старая отмена закроет свежий дескриптор. Именно так молча ломались
        // снимки экрана: второй `start()` следил за закрытым файлом, событий
        // не приходило, ошибок тоже.
        let watched = descriptor
        source.setCancelHandler { close(watched) }
        source.resume()
        watcher = source
    }

    private func rewatchIfNeeded() {
        guard watcher == nil else { return }
        watch()
    }

    private func check() {
        let mode = readMode()
        guard mode != currentMode else { return }
        currentMode = mode

        guard let mode else {
            center.upsert(
                Activity(
                    id: activityID,
                    title: t("ui.a70c53e2", "Фокусирование выключено"),
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
                subtitle: t("ui.d6137b6d", "Режим фокусирования"),
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
