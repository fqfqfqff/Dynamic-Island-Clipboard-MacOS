import AppKit
import SwiftUI

/// Полка: файлы, которые бросили на вырез.
///
/// Полка не копирует файлы и не двигает их — она держит ссылки. Смысл в том,
/// чтобы не искать файл в папке, когда его нужно перетащить куда-то ещё.
@MainActor
final class ShelfService: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let addedAt: Date
        var preview: NSImage?

        var name: String { url.lastPathComponent }

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id }
    }

    @Published private(set) var items: [Item] = []

    private let limit = 12

    private static var storeURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aura", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("shelf.json")
    }

    init() {
        restore()
    }

    func add(urls: [URL]) {
        for url in urls {
            // Один и тот же файл не кладём дважды.
            guard !items.contains(where: { $0.url == url }) else { continue }

            var item = Item(url: url, addedAt: Date(), preview: nil)
            item.preview = Self.preview(for: url)
            items.insert(item, at: 0)
        }

        if items.count > limit {
            items.removeLast(items.count - limit)
        }
        persist()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    /// На диск уходят только пути: превью дешевле построить заново, чем
    /// хранить, а сами файлы полка никогда не копирует.
    private func persist() {
        let paths = items.map(\.url.path)
        guard let data = try? JSONEncoder().encode(paths) else { return }
        try? data.write(to: Self.storeURL, options: .atomic)
    }

    private func restore() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let paths = try? JSONDecoder().decode([String].self, from: data)
        else { return }

        // Файл мог быть удалён или перемещён, пока приложение не работало.
        let urls = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        items = urls.map { url in
            Item(url: url, addedAt: Date(), preview: Self.preview(for: url))
        }
    }

    /// Уменьшенное превью: читается из файла через ImageIO, поэтому большой
    /// снимок не поднимается в память целиком.
    private static func preview(for url: URL) -> NSImage? {
        let side: CGFloat = 96

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: side * 2,
           ] as CFDictionary) {
            return NSImage(cgImage: image, size: CGSize(width: side, height: side))
        }

        // Не картинка — берём иконку типа файла.
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = CGSize(width: side, height: side)
        return icon
    }
}
