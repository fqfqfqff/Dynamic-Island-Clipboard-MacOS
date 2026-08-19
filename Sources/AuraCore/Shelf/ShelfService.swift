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
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
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
