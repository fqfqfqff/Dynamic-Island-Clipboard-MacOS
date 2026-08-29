import Foundation

/// Журнал уведомлений за день.
///
/// Прочитанное исчезает из выреза насовсем, и «что там было полчаса назад»
/// становится вопросом без ответа: в Центре уведомлений остаётся не всё,
/// а сгруппированное по приложениям и без порядка во времени.
///
/// Формат тот же, что у журнала буфера, — строка JSON на запись: его можно
/// читать чем угодно и дописывать без перезаписи файла.
enum NotificationArchive {
    struct Entry: Codable, Identifiable {
        let date: Date
        let app: String
        let sender: String
        let body: String?
        /// Идентификатор приложения — по нему в журнале берётся иконка.
        /// Необязательный: у записей, сделанных до его появления, его нет.
        var bundleID: String?

        var id: String { "\(date.timeIntervalSinceReferenceDate)|\(app)|\(sender)" }
    }

    /// Больше этого размера файл начинается заново: уведомления идут
    /// потоком, и расти без предела ему незачем.
    private static let limit = 4 * 1024 * 1024

    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aura", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("notifications.jsonl")
    }

    static func append(app: String, sender: String, body: String?, bundleID: String? = nil) {
        let entry = Entry(
            date: Date(), app: app, sender: sender, body: body, bundleID: bundleID
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(entry) else { return }
        data.append(0x0A)

        let url = fileURL
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }

        rotateIfNeeded(url)
    }

    /// Последние записи, новые сверху.
    static func recent(limit: Int = 200) -> [Entry] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return text
            .split(separator: "\n")
            .suffix(limit)
            .compactMap { decoder.decode(Entry.self, from: Data($0.utf8)) }
            .reversed()
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func rotateIfNeeded(_ url: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        guard let size, size > limit else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

private extension JSONDecoder {
    /// Битая строка не должна ронять весь разбор: журнал дописывается
    /// на ходу, и последняя строка бывает недописанной.
    func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decode(type, from: data) as T
    }
}
