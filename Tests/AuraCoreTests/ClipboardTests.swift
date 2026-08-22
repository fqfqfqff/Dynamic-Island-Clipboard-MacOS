import AppKit
import XCTest
@testable import AuraCore

final class ClipboardTests: XCTestCase {
    func testHexColorParsing() {
        XCTAssertNotNil(NSColor(hex: "#1E90FF"))
        XCTAssertNotNil(NSColor(hex: "#abc"), "короткая форма должна разбираться")
        XCTAssertNotNil(NSColor(hex: "#11223344"), "форма с прозрачностью должна разбираться")

        XCTAssertNil(NSColor(hex: "1E90FF"), "без решётки это не цвет")
        XCTAssertNil(NSColor(hex: "#GGGGGG"))
        XCTAssertNil(NSColor(hex: "#12345"))
        XCTAssertNil(NSColor(hex: ""))
    }

    func testHexRoundTrip() {
        let color = NSColor(hex: "#1E90FF")
        XCTAssertEqual(color?.hexString, "#1E90FF")
    }

    func testTitlesForEachKind() {
        let text = ClipboardItem(kind: .text("  привет  "), date: Date(), sourceName: nil)
        XCTAssertEqual(text.title, "привет", "заголовок должен быть без лишних пробелов")

        let blank = ClipboardItem(kind: .text("   "), date: Date(), sourceName: nil)
        XCTAssertEqual(blank.title, "Пробелы", "пустая строка не должна выглядеть как пустая карточка")

        let link = ClipboardItem(kind: .link(URL(string: "https://example.com/a/b")!),
                                 date: Date(), sourceName: nil)
        XCTAssertEqual(link.title, "example.com")

        let files = ClipboardItem(
            kind: .files([URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]),
            date: Date(), sourceName: nil
        )
        XCTAssertTrue(files.title.contains("2"))
    }

    func testStoreRoundTripKeepsEverythingButImages() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let items = [
            ClipboardItem(kind: .text("текст"), date: Date(), sourceName: "Xcode"),
            ClipboardItem(kind: .link(URL(string: "https://example.com")!), date: Date(), sourceName: nil),
            ClipboardItem(kind: .files([URL(fileURLWithPath: "/tmp/a.txt")]), date: Date(), sourceName: nil),
            ClipboardItem(kind: .color(NSColor(hex: "#1E90FF")!), date: Date(), sourceName: nil),
            ClipboardItem(kind: .image(NSImage(size: CGSize(width: 4, height: 4))), date: Date(), sourceName: nil),
        ]

        ClipboardStore.save(items, limit: 100, to: url)
        let restored = ClipboardStore.load(from: url)

        XCTAssertEqual(restored.count, 4, "картинки намеренно не сохраняются, остальное должно вернуться")
        XCTAssertEqual(restored.first?.title, "текст")
        XCTAssertEqual(restored.first?.sourceName, "Xcode")
    }

    func testStoreRespectsLimit() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let items = (0..<50).map {
            ClipboardItem(kind: .text("\($0)"), date: Date(), sourceName: nil)
        }
        ClipboardStore.save(items, limit: 10, to: url)

        XCTAssertEqual(ClipboardStore.load(from: url).count, 10)
    }

    func testLoadingMissingFileIsEmptyNotCrash() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aura-missing-\(UUID().uuidString).json")
        XCTAssertEqual(ClipboardStore.load(from: url).count, 0)
    }
}

extension ClipboardTests {
    func testArchiveSkipsImagesButKeepsEverythingElse() {
        let image = ClipboardItem(
            kind: .image(NSImage(size: CGSize(width: 2, height: 2))),
            date: Date(), sourceName: nil
        )
        let text = ClipboardItem(kind: .text("секрет дня"), date: Date(), sourceName: "Xcode")

        // Журнал пишется в общий файл приложения, поэтому проверяем сам отбор:
        // картинка записью стать не должна, текст — должен.
        XCTAssertNil(ClipboardArchive.testEntry(for: image))

        let entry = ClipboardArchive.testEntry(for: text)
        XCTAssertEqual(entry?.kind, "text")
        XCTAssertEqual(entry?.value, "секрет дня")
        XCTAssertEqual(entry?.source, "Xcode")
    }

    func testArchiveFlattensFileListsAndColors() {
        let files = ClipboardItem(
            kind: .files([URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")]),
            date: Date(), sourceName: nil
        )
        XCTAssertEqual(ClipboardArchive.testEntry(for: files)?.value, "/tmp/a\n/tmp/b")

        let color = ClipboardItem(kind: .color(NSColor(hex: "#1E90FF")!), date: Date(), sourceName: nil)
        XCTAssertEqual(ClipboardArchive.testEntry(for: color)?.value, "#1E90FF")
    }
}

@MainActor
extension ClipboardTests {
    /// Текст, положенный в буфер как UTF-8 и прочитанный однобайтовой
    /// кодировкой, превращается в «–њ—А–Є–≤–µ—В». Такое приходит от
    /// консольных утилит, и в истории это выглядело как мусор.
    func testRepairsMojibake() {
        let broken = "–њ—А–Є–≤–µ—В"
        XCTAssertEqual(ClipboardService.repairEncoding(broken), "привет")
    }

    func testLeavesNormalTextAlone() {
        XCTAssertEqual(ClipboardService.repairEncoding("привет, мир"), "привет, мир")
        XCTAssertEqual(ClipboardService.repairEncoding("hello world"), "hello world")
        XCTAssertEqual(ClipboardService.repairEncoding("тире — это не поломка"),
                       "тире — это не поломка")
    }
}

extension ClipboardTests {
    /// Поиск по журналу отбирает по содержимому и отдаёт свежее первым.
    func testArchiveSearchMatchesByContent() {
        let entries = [
            ClipboardArchive.Entry(date: Date(timeIntervalSince1970: 100),
                                   kind: "text", value: "первый токен", source: "Xcode"),
            ClipboardArchive.Entry(date: Date(timeIntervalSince1970: 200),
                                   kind: "text", value: "просто текст", source: nil),
            ClipboardArchive.Entry(date: Date(timeIntervalSince1970: 300),
                                   kind: "text", value: "второй токен", source: "Safari"),
        ]

        let found = ClipboardArchive.filter(entries, query: "токен", limit: 10)

        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found.first?.value, "второй токен", "свежие записи должны идти первыми")
    }

    func testArchiveSearchIgnoresCaseAndEmptyQuery() {
        let entries = [
            ClipboardArchive.Entry(date: Date(), kind: "text", value: "ТОКЕН", source: nil),
        ]
        XCTAssertEqual(ClipboardArchive.filter(entries, query: "токен", limit: 10).count, 1)
        XCTAssertTrue(ClipboardArchive.filter(entries, query: "", limit: 10).isEmpty)
    }

    func testArchiveSearchRespectsLimit() {
        let entries = (0..<50).map {
            ClipboardArchive.Entry(date: Date(timeIntervalSince1970: Double($0)),
                                   kind: "text", value: "совпадение \($0)", source: nil)
        }
        XCTAssertEqual(ClipboardArchive.filter(entries, query: "совпадение", limit: 5).count, 5)
    }
}

extension ClipboardTests {
    // MARK: - Код подтверждения

    /// macOS подставляет коды сама, но только в поля, которые сама
    /// и распознала. В терминале или в чужом приложении их набирают руками.
    func testCodeIsFoundNextToAWordAboutIt() {
        XCTAssertEqual(ClipboardItem.code(in: "Ваш код: 481596"), "481596")
        XCTAssertEqual(ClipboardItem.code(in: "Your verification code is 8123"), "8123")
        XCTAssertEqual(ClipboardItem.code(in: "Одноразовый пароль 12345"), "12345")
    }

    /// Иначе кодом станет любой год, цена и номер дома.
    func testDigitsWithoutContextAreNotACode() {
        XCTAssertNil(ClipboardItem.code(in: "Встречаемся в 1930 у дома 12"))
        XCTAssertNil(ClipboardItem.code(in: "8123"))
        XCTAssertNil(ClipboardItem.code(in: "код"), "цифр нет вовсе")
        XCTAssertNil(ClipboardItem.code(in: "код 1"), "одна цифра — не код")
    }

    // MARK: - Умные действия

    func testActionsDependOnWhatWasCopied() {
        let link = ClipboardItem(
            kind: .link(URL(string: "https://example.com")!), date: Date(), sourceName: nil
        )
        XCTAssertTrue(link.actions.contains { if case .openLink = $0 { true } else { false } })

        let json = ClipboardItem(kind: .text("{\"a\":1}"), date: Date(), sourceName: nil)
        XCTAssertTrue(json.actions.contains { if case .formatJSON = $0 { true } else { false } })

        let plain = ClipboardItem(kind: .text("просто текст"), date: Date(), sourceName: nil)
        XCTAssertTrue(plain.actions.isEmpty)
    }

    func testJSONIsRecognisedOnlyWhenItParses() {
        XCTAssertTrue(ClipboardItem.looksLikeJSON("{\"a\": 1}"))
        XCTAssertTrue(ClipboardItem.looksLikeJSON("[1, 2, 3]"))
        XCTAssertFalse(ClipboardItem.looksLikeJSON("{это не json}"))
        XCTAssertFalse(ClipboardItem.looksLikeJSON("обычный текст"))
    }

    func testJSONIsFormatted() throws {
        let pretty = try XCTUnwrap(ClipboardService.prettyJSON("{\"b\":2,\"a\":1}"))
        XCTAssertTrue(pretty.contains("\n"), "должен появиться перенос строк")
        XCTAssertLessThan(
            try XCTUnwrap(pretty.range(of: "\"a\"")).lowerBound,
            try XCTUnwrap(pretty.range(of: "\"b\"")).lowerBound,
            "ключи сортируются"
        )
    }
}
