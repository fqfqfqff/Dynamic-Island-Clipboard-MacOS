import AppKit

/// Сохраняет историю буфера между запусками.
///
/// Картинки на диск не пишутся: они тяжёлые, а история — вещь расходная.
/// Файлы и цвета хранятся как строки, поэтому переживают перезапуск целиком.
enum ClipboardStore {
    private struct Record: Codable {
        enum Kind: String, Codable {
            case text, link, files, color
        }

        let kind: Kind
        let value: String
        let extra: [String]
        let date: Date
        let source: String?
    }

    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aura", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("clipboard.json")
    }

    static func save(_ items: [ClipboardItem], limit: Int, to url: URL? = nil) {
        let records = items.prefix(limit).compactMap(record(from:))
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url ?? fileURL, options: .atomic)
    }

    static func load(from url: URL? = nil) -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: url ?? fileURL),
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return [] }
        return records.compactMap(item(from:))
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func record(from item: ClipboardItem) -> Record? {
        switch item.kind {
        case .text(let value):
            return Record(kind: .text, value: value, extra: [], date: item.date, source: item.sourceName)
        case .link(let url):
            return Record(kind: .link, value: url.absoluteString, extra: [], date: item.date, source: item.sourceName)
        case .files(let urls):
            return Record(
                kind: .files,
                value: urls.first?.path ?? "",
                extra: urls.dropFirst().map(\.path),
                date: item.date,
                source: item.sourceName
            )
        case .color(let color):
            return Record(kind: .color, value: color.hexString, extra: [], date: item.date, source: item.sourceName)
        case .image:
            return nil
        }
    }

    private static func item(from record: Record) -> ClipboardItem? {
        let kind: ClipboardItem.Kind
        switch record.kind {
        case .text:
            // Записи, сохранённые до починки кодировок, чинятся при загрузке.
            kind = .text(ClipboardService.repairEncoding(record.value))
        case .link:
            guard let url = URL(string: record.value) else { return nil }
            kind = .link(url)
        case .files:
            let paths = [record.value] + record.extra
            kind = .files(paths.map { URL(fileURLWithPath: $0) })
        case .color:
            guard let color = NSColor(hex: record.value) else { return nil }
            kind = .color(color)
        }
        return ClipboardItem(kind: kind, date: record.date, sourceName: record.source)
    }
}
