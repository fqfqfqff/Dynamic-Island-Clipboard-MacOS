import AppKit
import XCTest
@testable import AuraCore

/// Поиск иконки в снятой полосе баннера.
///
/// Снимаем всё поле слева от текста, потому что отступы у баннеров разные:
/// квадрат по формуле то срезал иконку, то захватывал пустой фон — у Gmail
/// в кадр попал один серый фон, и в вырезе висела «кривая фотка».
@MainActor
final class BannerIconTests: XCTestCase {

    /// Полоса баннера: тёмный фон, а в нём цветной квадрат иконки.
    private func strip(
        size: CGSize = CGSize(width: 58, height: 73),
        icon: CGRect,
        color: NSColor = .systemPink
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(white: 0.08, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        color.setFill()
        NSBezierPath(roundedRect: icon, xRadius: 8, yRadius: 8).fill()
        image.unlockFocus()
        return image
    }

    func testIconIsFoundInTheStrip() throws {
        let image = strip(icon: CGRect(x: 10, y: 18, width: 38, height: 38))
        let found = try XCTUnwrap(BannerIconReader.iconBounds(in: image))

        // Квадрат примерно со сторону иконки, а не со всю полосу.
        XCTAssertEqual(found.size.width, found.size.height, accuracy: 1)
        XCTAssertEqual(found.size.width, 38, accuracy: 8)
    }

    /// Иконка стоит не по центру полосы — так бывает у разных приложений,
    /// и именно на этом ломался расчёт по формуле.
    func testOffsetIconIsFoundToo() throws {
        let image = strip(icon: CGRect(x: 2, y: 30, width: 34, height: 34))
        let found = try XCTUnwrap(BannerIconReader.iconBounds(in: image))
        XCTAssertEqual(found.size.width, 34, accuracy: 8)
    }

    /// Пустая полоса — это не иконка, и подсовывать её вместо значка нельзя.
    func testEmptyStripGivesNothing() {
        let image = NSImage(size: CGSize(width: 58, height: 73))
        image.lockFocus()
        NSColor(white: 0.08, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 58, height: 73).fill()
        image.unlockFocus()

        XCTAssertNil(BannerIconReader.iconBounds(in: image))
    }

    /// Уголок с телефоном срезается, а размер остаётся честным: раньше
    /// обрезанное растягивалось обратно в полный квадрат, и иконка уезжала.
    func testBadgeTrimKeepsProportions() throws {
        let image = strip(
            size: CGSize(width: 40, height: 40),
            icon: CGRect(x: 0, y: 0, width: 40, height: 40)
        )
        let trimmed = BannerIconReader.withoutPhoneBadge(image)

        XCTAssertLessThan(trimmed.size.width, image.size.width)
        XCTAssertEqual(trimmed.size.width, trimmed.size.height, accuracy: 0.5)
    }
}

/// Устройства вывода: список и переключение.
///
/// В macOS смена вывода — это Пункт управления или ⌥-клик по значку звука.
/// Вырез уже знает, куда идёт звук, и переключать оттуда естественнее.
@MainActor
final class AudioOutputTests: XCTestCase {
    /// Хотя бы одно устройство вывода есть на любой машине — встроенные
    /// динамики никуда не денутся.
    func testThereIsAlwaysSomewhereToPlay() {
        let devices = AudioOutputs.list()
        XCTAssertFalse(devices.isEmpty, "не нашлось ни одного выхода")
        XCTAssertTrue(devices.allSatisfy { !$0.name.isEmpty })
    }

    /// Текущее ровно одно: список помечает его, и не больше одного.
    func testExactlyOneIsCurrent() {
        let current = AudioOutputs.list().filter(\.isCurrent)
        XCTAssertEqual(current.count, 1)
        XCTAssertEqual(current.first?.name, AudioOutputs.current()?.name)
    }

    /// Микрофоны в список не попадают: у них нет выходных каналов.
    func testOnlyOutputsAreListed() {
        let names = AudioOutputs.list().map { $0.name.lowercased() }
        XCTAssertFalse(names.contains { $0.contains("микрофон") || $0.contains("microphone") })
    }
}
