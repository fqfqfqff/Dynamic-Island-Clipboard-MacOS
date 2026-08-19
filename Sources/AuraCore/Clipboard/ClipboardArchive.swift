import AppKit

/// Полный журнал копирований — всё, что попадало в буфер, кроме картинок.
///
/// В отличие от истории, журнал ничем не ограничен и не чистится кнопкой
/// «очистить историю»: это архив, а не список для вставки. Формат — по одной
/// JSON-записи на строку, чтобы файл можно было дописывать и читать построчно.
///
/// Содержимое, помеченное как приватное (`org.nspasteboard.ConcealedType`),
/// сюда не доходит: такие записи отсекаются ещё в `ClipboardService`.
enum ClipboardArchive {
    struct Entry: Codable {
        let date: Date
        let kind: String
        let value: String
        let source: String?
    }

    /// Больше этого размера файл уходит в архив с суффиксом `.1`.
    private static let rotationLimit = 20 * 1024 * 1024

    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aura", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("clipboard-log.jsonl")
    }

    static func append(_ item: ClipboardItem) {
        guard let entry = entry(for: item) else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(entry) else { return }
        data.append(0x0A)   // перевод строки

        rotateIfNeeded()

        let url = fileURL
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func entryCount() -> Int {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n").count
    }

    static func revealInFinder() {
        let url = fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data().write(to: url)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Открыто для тестов: отбор записей — единственная логика, которую
    /// стоит проверять, не трогая файл на диске.
    static func testEntry(for item: ClipboardItem) -> Entry? { entry(for: item) }

    private static func entry(for item: ClipboardItem) -> Entry? {
        let kind: String
        let value: String

        switch item.kind {
        case .text(let text):
            kind = "text"
            value = text
        case .link(let url):
            kind = "link"
            value = url.absoluteString
        case .files(let urls):
            kind = "files"
            value = urls.map(\.path).joined(separator: "\n")
        case .color(let color):
            kind = "color"
            value = color.hexString
        case .image:
            // Картинки в журнал не пишем: он должен оставаться читаемым текстом.
            return nil
        }

        return Entry(date: item.date, kind: kind, value: value, source: item.sourceName)
    }

    private static func rotateIfNeeded() {
        let url = fileURL
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int, size > rotationLimit
        else { return }

        let archived = url.deletingLastPathComponent()
            .appendingPathComponent("clipboard-log.1.jsonl")
        try? FileManager.default.removeItem(at: archived)
        try? FileManager.default.moveItem(at: url, to: archived)
    }
}
