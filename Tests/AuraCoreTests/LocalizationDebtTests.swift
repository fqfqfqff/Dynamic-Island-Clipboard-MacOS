import XCTest
@testable import AuraCore

/// Строки интерфейса обязаны проходить через `t()`.
///
/// Иначе на английском они останутся русскими: перевод берётся из словаря
/// по ключу, а литерал в коде до словаря не доходит. Заметить это на своей
/// машине невозможно — у неё системный язык русский.
///
/// Долг уже накоплен, и разом его не закрыть. Поэтому проверка работает
/// храповиком: текущее число заморожено, и любая новая непереведённая
/// строка роняет сборку с указанием, какая именно.
final class LocalizationDebtTests: XCTestCase {

    /// Сколько строк интерфейса ещё не переведено. Уменьшать можно,
    /// увеличивать нельзя.
    /// Ноль. Долга больше нет: всё, что видит человек, идёт через перевод.
    /// Держать этот ноль важнее, чем кажется, — окно настроек однажды
    /// уже расходилось с переводом на семьдесят строк.
    private let allowed = 0

    /// Места, где строка попадает на экран.
    private let interface = [
        #"Text\(\s*""#, #"hint\(\s*""#, #"group\(\s*""#, #"\.help\(\s*""#,
        #"Toggle\(\s*""#, #"Button\(\s*""#, #"Label\(\s*""#, #"slider\(\s*""#,
        #"title:\s*""#, #"subtitle:\s*""#,
    ]

    func testInterfaceStringsGoThroughTranslation() throws {
        let sources = try packageRoot().appendingPathComponent("Sources")
        var offenders: [String] = []

        for file in try swiftFiles(in: sources) where !file.path.contains("Snapshots") {
            let text = try String(contentsOf: file, encoding: .utf8)

            for (number, line) in text.components(separatedBy: .newlines).enumerated() {
                // Комментарии по-русски — это норма, они и должны быть такими.
                let code = line.components(separatedBy: "//")[0]
                guard !code.contains(#"t(""#) else { continue }
                guard interface.contains(where: { code.range(of: $0, options: .regularExpression) != nil })
                else { continue }

                for literal in Self.literals(in: code) where literal.containsCyrillic {
                    offenders.append("\(file.lastPathComponent):\(number + 1) «\(literal)»")
                }
            }
        }

        if offenders.count > allowed {
            let extra = offenders.suffix(offenders.count - allowed).joined(separator: "\n  ")
            XCTFail("""
                Непереведённых строк интерфейса стало больше: \(offenders.count) вместо \(allowed).
                Оберните новые строки в t("ui.<ключ>", "текст") и добавьте перевод
                в обе Localizable.strings. Похоже на новые:
                  \(extra)
                """)
        }

        // Долг уменьшился — порог пора опустить, иначе храповик проворачивается.
        XCTAssertGreaterThanOrEqual(
            offenders.count, allowed - 5,
            "долг заметно сократился: опустите `allowed` до \(offenders.count)"
        )
    }

    // MARK: - Опоры

    private static func literals(in line: String) -> [String] {
        var result: [String] = []
        var current: String?

        for character in line {
            if character == "\"" {
                if let value = current {
                    result.append(value)
                    current = nil
                } else {
                    current = ""
                }
            } else if current != nil {
                current?.append(character)
            }
        }
        return result
    }

    private func packageRoot() throws -> URL {
        // Tests/AuraCoreTests/<этот файл> → корень пакета на два уровня выше.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func swiftFiles(in folder: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: nil
        ) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}

private extension String {
    var containsCyrillic: Bool {
        contains { $0.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) } }
    }
}
