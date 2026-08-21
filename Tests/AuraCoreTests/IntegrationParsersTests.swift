import XCTest
@testable import AuraCore

final class IntegrationParsersTests: XCTestCase {

    func testReadsBannerAsAppTitleAndBody() {
        let content = NotificationMirrorProvider.content(from: [
            "Telegram", "Никита", "привет, как дела?",
        ])

        XCTAssertEqual(content?.app, "Telegram")
        XCTAssertEqual(content?.sender, "Никита")
        XCTAssertEqual(content?.body, "привет, как дела?")
    }

    func testBannerWithoutBodyIsStillValid() {
        let content = NotificationMirrorProvider.content(from: ["Календарь", "Через 10 минут"])
        XCTAssertEqual(content?.sender, "Через 10 минут")
        XCTAssertNil(content?.body)
    }

    func testSkipsServiceLabelsAndTooShortBanners() {
        XCTAssertNil(NotificationMirrorProvider.content(from: ["Telegram"]),
                     "из одной строки уведомления не собрать")
        XCTAssertNil(NotificationMirrorProvider.content(from: ["Telegram", "  ", "Закрыть"]),
                     "служебные подписи не должны становиться заголовком")
    }

    /// Узлы после отправителя — это разные поля баннера, а не строки одного
    /// текста: многострочный текст система отдаёт одним узлом. Поэтому они
    /// и разделяются точкой, а не склеиваются в предложение.
    func testExtraFieldsAreJoinedWithSeparator() {
        let content = NotificationMirrorProvider.content(from: [
            "Почта", "Тема письма", "рабочий ящик", "текст письма",
        ])
        XCTAssertEqual(content?.body, "рабочий ящик · текст письма")
    }

    // MARK: - Фокусирование

    func testKnownFocusModesGetHumanNames() {
        XCTAssertEqual(
            FocusActivityProvider.humanName(for: "com.apple.donotdisturb.mode.default"),
            "Не беспокоить"
        )
        XCTAssertEqual(FocusActivityProvider.humanName(for: "com.apple.focus.work"), "Работа")
        XCTAssertEqual(FocusActivityProvider.symbol(for: "com.apple.sleep.sleep-mode"), "bed.double.fill")
    }

    func testCustomFocusModeFallsBackGracefully() {
        let identifier = "com.apple.focus.custom.9A7F-1234"
        XCTAssertEqual(FocusActivityProvider.humanName(for: identifier), "Фокусирование")
        XCTAssertEqual(FocusActivityProvider.symbol(for: identifier), "moon.fill")
    }
}

extension IntegrationParsersTests {
    func testCountdownReadsNaturally() {
        XCTAssertEqual(CalendarActivityProvider.countdown(minutes: 1), "через минуту")
        XCTAssertEqual(CalendarActivityProvider.countdown(minutes: 3), "через 3 минуты")
        XCTAssertEqual(CalendarActivityProvider.countdown(minutes: 12), "через 12 минут")
        XCTAssertEqual(CalendarActivityProvider.countdown(minutes: 0), "меньше минуты")
        XCTAssertEqual(CalendarActivityProvider.countdown(minutes: -2), "вот-вот")
    }
}

extension IntegrationParsersTests {
    /// Играющее приложение важнее системного посредника AirPlay.
    func testLocalAppWinsOverAirPlay() {
        let airplay = AudioProcessMonitor.Source(
            objectID: 1, pid: 1,
            bundleID: "com.apple.AirPlayXPCHelper", name: "AirPlayXPCHelper", kind: .helper
        )
        let spotify = AudioProcessMonitor.Source(
            objectID: 2, pid: 2,
            bundleID: "com.spotify.client", name: "Spotify", kind: .player
        )

        XCTAssertTrue(airplay.isAirPlay)
        XCTAssertFalse(spotify.isAirPlay)
        XCTAssertEqual(AudioProcessMonitor.preferred(from: [airplay, spotify])?.name, "Spotify")
        XCTAssertEqual(AudioProcessMonitor.preferred(from: [airplay])?.name, "AirPlayXPCHelper")
    }
}

extension IntegrationParsersTests {
    /// Версии сравниваются по числам: строкой «0.10.0» оказалось бы старше «0.9.0».
    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("0.2.0", than: "0.1.0"))
        XCTAssertTrue(UpdateChecker.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.1.0", than: "0.2.0"))
        XCTAssertFalse(UpdateChecker.isNewer("мусор", than: "0.1.0"))
    }
}

extension IntegrationParsersTests {
    // MARK: - Загрузки

    /// Браузер пишет во временный файл рядом с будущим результатом:
    /// имя после загрузки — это имя без служебного хвоста.
    func testFinalNameDropsTemporaryExtension() {
        XCTAssertEqual(
            DownloadActivityProvider.finalName(
                for: URL(fileURLWithPath: "/x/отчёт.pdf.crdownload")
            ),
            "отчёт.pdf"
        )
        XCTAssertEqual(
            DownloadActivityProvider.finalName(for: URL(fileURLWithPath: "/x/фильм.mkv.part")),
            "фильм.mkv"
        )
        // У Safari временный файл — это папка «Имя.download».
        XCTAssertEqual(
            DownloadActivityProvider.finalName(for: URL(fileURLWithPath: "/x/архив.zip.download")),
            "архив.zip"
        )
    }

    /// Процентов у нас нет и быть не может: полного размера из временного
    /// файла не узнать. Показываем то, что знаем точно.
    func testSizeWordingInsteadOfFakePercentage() {
        XCTAssertEqual(DownloadActivityProvider.wording(size: 0), "Начинается")
        XCTAssertTrue(DownloadActivityProvider.wording(size: 5_000_000).contains("MB")
                      || DownloadActivityProvider.wording(size: 5_000_000).contains("МБ"))
    }
}
