import AppKit

struct ClipboardItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case text(String)
        case link(URL)
        case image(NSImage)
        case files([URL])
        case color(NSColor)
    }

    let id = UUID()
    let kind: Kind
    let date: Date
    let sourceName: String?

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool { lhs.id == rhs.id }

    /// Содержимое одинаковое — значит новый элемент создавать не нужно.
    func hasSameContent(as other: ClipboardItem) -> Bool { kind == other.kind }

    var symbol: String {
        switch kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .files: "doc"
        case .color: "paintpalette"
        }
    }

    var title: String {
        switch kind {
        case .text(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Пробелы" : trimmed
        case .link(let url):
            return url.host ?? url.absoluteString
        case .image(let image):
            return "Изображение \(Int(image.size.width))×\(Int(image.size.height))"
        case .files(let urls):
            return urls.count == 1
                ? urls[0].lastPathComponent
                : "\(urls.count) файла(ов)"
        case .color(let color):
            return color.hexString
        }
    }
}

extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
}
