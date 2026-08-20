import XCTest
@testable import AuraCore

final class LocalizationTests: XCTestCase {
    /// Ключ, которого нет в переводах, вернёт запасной русский текст —
    /// интерфейс не сломается, но и переведён не будет.
    func testFallbackIsUsedForUnknownKeys() {
        XCTAssertEqual(t("ui.несуществующий", "запасной текст"), "запасной текст")
    }

    func testBothLanguagesHaveTheSameKeys() throws {
        let bundle = Bundle.module

        let english = try keys(in: bundle, locale: "en")
        let russian = try keys(in: bundle, locale: "ru")

        XCTAssertFalse(english.isEmpty, "английские строки должны быть в бандле")
        XCTAssertEqual(
            english.symmetricDifference(russian), [],
            "наборы ключей разошлись — часть интерфейса останется без перевода"
        )
    }

    func testEnglishStringsAreActuallyTranslated() throws {
        let bundle = Bundle.module
        let english = try contents(in: bundle, locale: "en")

        // Кириллица в английском файле означает непереведённую строку.
        let untranslated = english.filter { $0.value.contains(where: { $0.isCyrillic }) }
        XCTAssertTrue(
            untranslated.isEmpty,
            "без перевода остались: \(untranslated.values.prefix(3).joined(separator: ", "))"
        )
    }

    private func contents(in bundle: Bundle, locale: String) throws -> [String: String] {
        let url = try XCTUnwrap(
            bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: locale),
            "не найден файл строк для \(locale)"
        )
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String])
    }

    private func keys(in bundle: Bundle, locale: String) throws -> Set<String> {
        Set(try contents(in: bundle, locale: locale).keys)
    }
}

private extension Character {
    var isCyrillic: Bool {
        unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }
}
