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
    /// Закреплённые элементы держатся наверху и не вытесняются лимитом.
    var isPinned: Bool = false
    /// Оформленный вариант текста, если он был в буфере.
    ///
    /// Хранится рядом с `kind`, а не внутри: одинаковый текст остаётся
    /// одинаковым независимо от того, был ли он жирным, — иначе одна и та же
    /// строка из разных приложений плодила бы дубли в истории.
    var richText: Data?

    var hasFormatting: Bool { richText != nil }

    /// Скопировано на другом устройстве и доехало универсальным буфером.
    ///
    /// macOS об этом никак не сообщает: содержимое просто появляется
    /// в буфере, и узнать, что оно с телефона, можно только по служебной
    /// метке на пастборде.
    var fromOtherDevice: Bool = false

    /// Код подтверждения внутри текста.
    ///
    /// macOS подставляет коды из «Сообщений» сама, но только в поля,
    /// которые сама и распознала: в терминале, в чужом приложении или
    /// на сайте, который она не поняла, приходится набирать руками.
    var verificationCode: String? {
        guard case .text(let value) = kind else { return nil }
        return Self.code(in: value)
    }

    /// Ищем короткое число рядом со словом про код.
    ///
    /// Просто «четыре цифры подряд» брать нельзя — так любой год, цена
    /// и номер дома становятся кодом подтверждения.
    static func code(in text: String) -> String? {
        let lowered = text.lowercased()
        let markers = [
            "код", "kod", "code", "пароль", "otp", "verification", "подтверж",
            "одноразов", "passcode", "pin",
        ]
        guard markers.contains(where: lowered.contains) else { return nil }
        guard text.count <= 200 else { return nil }

        let digits = text.split { !$0.isNumber }.map(String.init)
        return digits.first { (4...8).contains($0.count) }
    }

    /// Что осмысленно сделать с этим содержимым.
    ///
    /// Действия зависят от типа: ссылку открыть, цвет перевести в другую
    /// запись, файл показать в Finder. Раньше типы распознавались, но
    /// ничего не давали — только значок слева.
    enum Action: Identifiable {
        case openLink(URL)
        case revealFiles([URL])
        case colorAsRGB(NSColor)
        case formatJSON(String)
        case pasteCode(String)

        var id: String { title }

        var title: String {
            switch self {
            case .openLink: t("ui.1259571a", "Открыть")
            case .revealFiles: t("ui.9e3e457e", "Показать в Finder")
            case .colorAsRGB: t("ui.5c8b21a0", "Скопировать как RGB")
            case .formatJSON: t("ui.7e3a91d4", "Отформатировать JSON")
            case .pasteCode: t("ui.2b6f40e1", "Вставить код")
            }
        }

        var symbol: String {
            switch self {
            case .openLink: "arrow.up.right.square"
            case .revealFiles: "folder"
            case .colorAsRGB: "paintpalette"
            case .formatJSON: "curlybraces"
            case .pasteCode: "key.horizontal"
            }
        }
    }

    var actions: [Action] {
        var result: [Action] = []
        if let code = verificationCode { result.append(.pasteCode(code)) }

        switch kind {
        case .link(let url):
            result.append(.openLink(url))
        case .files(let urls):
            result.append(.revealFiles(urls))
        case .color(let color):
            result.append(.colorAsRGB(color))
        case .text(let value):
            if Self.looksLikeJSON(value) { result.append(.formatJSON(value)) }
        case .image:
            break
        }
        return result
    }

    static func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 2,
              (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
                || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
        else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
    }

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
