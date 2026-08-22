import XCTest
@testable import AuraCore

/// Слежение за папкой снимков.
///
/// Провайдер молча не работал: `start()` вызывается не один раз, а обработчик
/// отмены закрывал дескриптор через `self` — то есть уже новый, а не свой.
/// Второе слежение оказывалось за закрытым файлом. Ни ошибки, ни события —
/// снимки просто никогда не появлялись.
@MainActor
final class ScreenshotWatchTests: XCTestCase {
    private var folder: URL!
    private var provider: ScreenshotActivityProvider!
    private var clipboard: ClipboardService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let settings = SettingsStore(defaults: TestDefaults.make())
        // Иначе служба поднимет настоящую историю буфера пользователя —
        // и, что хуже, запишет в неё то, что насоздавал тест.
        settings.persistClipboard = false
        settings.archiveEverything = false
        // И системный буфер тоже не трогаем: тест не имеет права выкидывать
        // то, что человек только что скопировал. Запись в буфер проверяется
        // отдельно, на своём пастборде.
        settings.copyScreenshotToClipboard = false
        clipboard = ClipboardService(settings: settings)
        provider = ScreenshotActivityProvider(
            center: ActivityCenter(),
            clipboard: clipboard,
            settings: settings,
            folder: folder
        )
    }

    override func tearDownWithError() throws {
        provider.stop()
        try? FileManager.default.removeItem(at: folder)
        try super.tearDownWithError()
    }

    private func dropScreenshot() throws {
        let png = Data(base64Encoded: """
            iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGP8z8Dwn4GBgYGJAQ0AABZoAQ+8PQxLAAAAAElFTkSuQmCC
            """)!
        try png.write(to: folder.appendingPathComponent("Снимок экрана 2026-08-22.png"))
    }

    /// Прокрутить главную очередь: отмена прежнего слежения приходит
    /// асинхронно, и без прокрутки она бы отработала не в том порядке,
    /// в котором это происходит в приложении.
    private func pump(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func waitForItem() {
        let deadline = Date().addingTimeInterval(4)
        while clipboard.items.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    func testNoticesANewScreenshot() throws {
        provider.start()
        try dropScreenshot()
        waitForItem()

        XCTAssertEqual(clipboard.items.count, 1)
    }

    /// Тот самый случай: `applyProviderSettings` зовут не один раз.
    func testStillWatchesAfterRestart() throws {
        provider.start()
        provider.start()
        pump(0.3)

        try dropScreenshot()
        waitForItem()

        XCTAssertEqual(clipboard.items.count, 1, "второе слежение смотрело в закрытый дескриптор")
    }
}
