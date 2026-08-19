import AppKit

/// Снимок того, что играет, для внешних потребителей — прежде всего для
/// заставки, которая живёт в отдельном процессе и до объектов приложения
/// дотянуться не может.
///
/// Файл лежит в /Users/Shared: процесс заставки работает в песочнице, и это
/// одно из немногих мест, куда он гарантированно имеет доступ.
public struct NowPlayingSnapshot: Codable {
    public var title: String
    public var subtitle: String?
    public var appName: String
    public var isPlaying: Bool
    public var duration: TimeInterval?
    public var elapsed: TimeInterval?
    public var elapsedAt: Date
    public var accentHex: String
    public var artworkPath: String?
    /// Строки песни на момент снимка — заставка сама текст не тянет.
    public var lyricPrevious: String?
    public var lyric: String?
    public var lyricNext: String?
    public var updatedAt: Date

    public static var folderURL: URL {
        URL(fileURLWithPath: "/Users/Shared/Aura", isDirectory: true)
    }

    public static var fileURL: URL {
        folderURL.appendingPathComponent("nowplaying.json")
    }

    public static var artworkURL: URL {
        folderURL.appendingPathComponent("artwork.png")
    }

    /// Насколько снимок свежий. Заставка по этому решает, показывать плеер
    /// или только часы: приложение могло быть закрыто.
    public var isFresh: Bool {
        Date().timeIntervalSince(updatedAt) < 30
    }

    public func progressNow() -> Double? {
        guard let duration, duration > 0, let elapsed else { return nil }
        let drift = isPlaying ? Date().timeIntervalSince(elapsedAt) : 0
        return min(1, max(0, (elapsed + drift) / duration))
    }

    public func elapsedNow() -> TimeInterval? {
        guard let elapsed else { return nil }
        let drift = isPlaying ? Date().timeIntervalSince(elapsedAt) : 0
        return min(duration ?? .greatestFiniteMagnitude, elapsed + drift)
    }

    public static func read() -> NowPlayingSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NowPlayingSnapshot.self, from: data)
    }

    public func write() {
        try? FileManager.default.createDirectory(
            at: Self.folderURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    /// Обложка кладётся рядом отдельным файлом: JSON с картинкой внутри
    /// раздувался бы до сотен килобайт на каждую перезапись.
    public static func writeArtwork(_ image: NSImage?) -> String? {
        guard let image,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            try? FileManager.default.removeItem(at: artworkURL)
            return nil
        }

        try? FileManager.default.createDirectory(
            at: folderURL, withIntermediateDirectories: true
        )
        try? png.write(to: artworkURL, options: .atomic)
        return artworkURL.path
    }
}

extension NSColor {
    var hexStringForSnapshot: String { hexString }
}
