import Foundation
import SQLite3

/// Уведомления из базы Центра уведомлений.
///
/// Зеркало читает баннеры, но баннеров может не быть вовсе: при включённом
/// «Не беспокоить» система не показывает их, а в настройках macOS их можно
/// выключить у любого приложения. Уведомление при этом приходит — просто
/// молча, сразу в Центр уведомлений.
///
/// База лежит в защищённой папке и требует полного доступа к диску — того
/// самого, который уже нужен режиму фокусирования.
@MainActor
final class NotificationStore {
    struct Record: Equatable {
        let id: Int64
        let bundleID: String
        let title: String
        let subtitle: String?
        let body: String?
        let date: Date
    }

    private var lastSeen: Int64 = 0
    private var watcher: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var pending: DispatchWorkItem?

    private var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
    }

    var isAvailable: Bool {
        FileManager.default.isReadableFile(atPath: databaseURL.path)
    }

    /// Последние записи, новее уже виденных.
    ///
    /// База в режиме WAL: открыть её только на чтение нельзя — SQLite хочет
    /// создать рядом служебный файл. Поэтому работаем с копией: заодно
    /// не трогаем чужие данные вовсе.
    func newRecords(limit: Int = 10) -> [Record] {
        guard let copy = makeCopy() else { return [] }
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else { return [] }
        defer { sqlite3_close(handle) }

        let sql = """
            SELECT record.rec_id, app.identifier, record.data, record.delivered_date
            FROM record JOIN app ON app.app_id = record.app_id
            ORDER BY record.rec_id DESC LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))

        var result: [Record] = []
        var newest = lastSeen

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            newest = max(newest, id)
            guard id > lastSeen, lastSeen > 0 else {
                // Первый заход только запоминает границу: показывать всё,
                // что накопилось за день, никто не просил.
                continue
            }

            guard let identifier = sqlite3_column_text(statement, 1),
                  let blob = sqlite3_column_blob(statement, 2)
            else { continue }

            let size = Int(sqlite3_column_bytes(statement, 2))
            let data = Data(bytes: blob, count: size)
            let seconds = sqlite3_column_double(statement, 3)

            guard let parsed = Self.parse(data) else { continue }
            result.append(
                Record(
                    id: id,
                    bundleID: String(cString: identifier),
                    title: parsed.title,
                    subtitle: parsed.subtitle,
                    body: parsed.body,
                    date: Date(timeIntervalSinceReferenceDate: seconds)
                )
            )
        }

        lastSeen = newest
        return result.reversed()
    }

    /// Следит за базой и зовёт обратно, когда в ней появилось новое.
    ///
    /// Пишет система в журнал (`db-wal`), поэтому следим именно за ним.
    /// Опрашивать базу по таймеру нельзя: каждое чтение — копия файла.
    func watch(onNew: @escaping ([Record]) -> Void) {
        stop()
        guard isAvailable else { return }

        let journal = URL(fileURLWithPath: databaseURL.path + "-wal")
        let path = FileManager.default.fileExists(atPath: journal.path)
            ? journal.path : databaseURL.path

        descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.journalChanged(onNew: onNew) }
        }

        // Дескриптор захватывается значением: отмена приходит асинхронно,
        // и к этому моменту `self.descriptor` может указывать уже на новый.
        let watched = descriptor
        source.setCancelHandler { close(watched) }
        source.resume()
        watcher = source

        // Первое чтение — только чтобы запомнить границу.
        _ = newRecords()
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        descriptor = -1
        pending?.cancel()
        pending = nil
    }

    /// Журнал меняется пачками: система пишет запись, тут же обновляет
    /// её состояние, потом ещё раз. Читаем один раз, когда всё уляжется.
    private func journalChanged(onNew: @escaping ([Record]) -> Void) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let fresh = self.newRecords()
                guard !fresh.isEmpty else { return }
                onNew(fresh)
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Колонки всех таблиц и размеры двоичных полей — ищем иконку.
    func columns() -> [String] {
        guard let copy = makeCopy() else { return ["копию сделать не вышло"] }
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else { return ["база не открылась"] }
        defer { sqlite3_close(handle) }

        var tables: [String] = []
        var list: OpaquePointer?
        if sqlite3_prepare_v2(
            handle, "SELECT name FROM sqlite_master WHERE type='table'", -1, &list, nil
        ) == SQLITE_OK {
            while sqlite3_step(list) == SQLITE_ROW {
                if let text = sqlite3_column_text(list, 0) { tables.append(String(cString: text)) }
            }
        }
        sqlite3_finalize(list)

        var lines: [String] = []
        for table in tables {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                handle, "SELECT * FROM \"\(table)\" LIMIT 1", -1, &statement, nil
            ) == SQLITE_OK else { continue }

            var described: [String] = []
            if sqlite3_step(statement) == SQLITE_ROW {
                for index in 0..<sqlite3_column_count(statement) {
                    let name = sqlite3_column_name(statement, index).map { String(cString: $0) } ?? "?"
                    let type = sqlite3_column_type(statement, index)
                    let size = sqlite3_column_bytes(statement, index)
                    let kind = type == SQLITE_BLOB ? "двоичное \(size) байт" : "\(type)"
                    described.append("\(name):\(kind)")
                }
            }
            sqlite3_finalize(statement)
            lines.append("\(table) → " + described.joined(separator: ", "))
        }
        return lines
    }

    /// Все ключи записи — чтобы понять, что ещё лежит в базе.
    func peekKeys(limit: Int = 6) -> [String] {
        guard let copy = makeCopy() else { return ["копию сделать не вышло"] }
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else { return ["база не открылась"] }
        defer { sqlite3_close(handle) }

        let sql = "SELECT record.rec_id, app.identifier, record.data FROM record "
            + "JOIN app ON app.app_id = record.app_id ORDER BY record.rec_id DESC LIMIT ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))

        var lines: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let app = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "?"
            guard let blob = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 2)))

            guard let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any] else { continue }

            var described: [String] = []
            for (key, value) in plist.sorted(by: { $0.key < $1.key }) {
                if let nested = value as? [String: Any] {
                    described.append("\(key){" + nested.keys.sorted().joined(separator: ",") + "}")
                } else if let bytes = value as? Data {
                    described.append("\(key)=данные \(bytes.count) байт")
                } else {
                    described.append("\(key)=\(String(describing: value).prefix(40))")
                }
            }
            lines.append("\(app): " + described.joined(separator: "  "))
        }
        return lines
    }

    /// Свежие записи как есть — для разбора формата.
    func peek(limit: Int = 4) -> [String] {
        guard let copy = makeCopy() else { return ["копию сделать не вышло"] }
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else { return ["база не открылась"] }
        defer { sqlite3_close(handle) }

        let sql = "SELECT record.rec_id, app.identifier, record.data, record.delivered_date "
            + "FROM record JOIN app ON app.app_id = record.app_id "
            + "ORDER BY record.delivered_date DESC LIMIT ?"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            return ["запрос не собрался: " + String(cString: sqlite3_errmsg(handle))]
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))

        var lines: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let app = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "?"
            let seconds = sqlite3_column_double(statement, 3)
            let when = Date(timeIntervalSinceReferenceDate: seconds)
                .formatted(date: .omitted, time: .standard)

            var text = "не разобрано"
            if let blob = sqlite3_column_blob(statement, 2) {
                let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 2)))
                if let parsed = Self.parse(data) {
                    text = [parsed.title, parsed.subtitle ?? "—", parsed.body ?? "—"]
                        .joined(separator: " | ")
                } else if let plist = try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil
                ) as? [String: Any] {
                    text = "ключи: " + plist.keys.sorted().joined(separator: ",")
                }
            }
            lines.append("#\(id) \(when) \(app) → \(text)")
        }
        return lines
    }

    /// Что вообще лежит в базе — имена таблиц и число строк.
    /// Только для разбора: формат базы меняется от версии к версии.
    func schema() -> [String] {
        guard let copy = makeCopy() else { return ["копию сделать не вышло"] }
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else { return ["база не открылась"] }
        defer { sqlite3_close(handle) }

        var names: [String] = []
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(
            handle, "SELECT name FROM sqlite_master WHERE type='table'", -1, &statement, nil
        ) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    names.append(String(cString: text))
                }
            }
        }
        sqlite3_finalize(statement)

        return names.map { name in
            var count: OpaquePointer?
            var rows = 0
            if sqlite3_prepare_v2(handle, "SELECT count(*) FROM \"\(name)\"", -1, &count, nil)
                == SQLITE_OK, sqlite3_step(count) == SQLITE_ROW {
                rows = Int(sqlite3_column_int64(count, 0))
            }
            sqlite3_finalize(count)
            return "\(name): \(rows)"
        }
    }

    /// Содержимое записи — двоичный plist внутри поля `data`.
    static func parse(_ data: Data) -> (title: String, subtitle: String?, body: String?)? {
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else { return nil }

        // Само уведомление лежит в `req`; ключи короткие и старые как мир.
        let request = plist["req"] as? [String: Any] ?? plist
        let title = request["titl"] as? String
        let subtitle = request["subt"] as? String
        let body = request["body"] as? String

        guard let title, !title.isEmpty else { return nil }
        return (title, subtitle, body)
    }

    /// Копия базы вместе со служебными файлами журнала.
    private func makeCopy() -> URL? {
        let manager = FileManager.default
        guard manager.isReadableFile(atPath: databaseURL.path) else { return nil }

        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aura-notifications-\(UUID().uuidString)")
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)

        let target = folder.appendingPathComponent("db")
        do {
            try manager.copyItem(at: databaseURL, to: target)
            for suffix in ["-wal", "-shm"] {
                let extra = URL(fileURLWithPath: databaseURL.path + suffix)
                guard manager.fileExists(atPath: extra.path) else { continue }
                try? manager.copyItem(at: extra, to: URL(fileURLWithPath: target.path + suffix))
            }
            return target
        } catch {
            try? manager.removeItem(at: folder)
            return nil
        }
    }
}
