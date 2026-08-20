import XCTest
@testable import AuraCore

final class IntegrationParsersTests: XCTestCase {

    // MARK: - Заряд наушников

    func testParsesAirPodsBatteryLevels() {
        let output = """
              Connected:
                  AirPods (Мой):
                      Address: 08:5D:53:D5:16:7D
                      Case Battery Level: 34 %
                      Left Battery Level: 48 %
                      Right Battery Level: 52 %
                  Magic Mouse:
                      Battery Level: 71 %
        """

        let parsed = BluetoothActivityProvider.parseBatteries(from: output)

        XCTAssertEqual(parsed["AirPods (Мой)"]?.left, 48)
        XCTAssertEqual(parsed["AirPods (Мой)"]?.right, 52)
        XCTAssertEqual(parsed["AirPods (Мой)"]?.caseLevel, 34)
        XCTAssertEqual(parsed["AirPods (Мой)"]?.displayValue, 48,
                       "показывать нужно меньший наушник — он сядет первым")

        XCTAssertEqual(parsed["Magic Mouse"]?.single, 71)
        XCTAssertEqual(parsed["Magic Mouse"]?.displayValue, 71)
    }

    func testIgnoresDevicesWithoutBattery() {
        let output = """
              Connected:
                  Клавиатура:
                      Address: 11:22:33:44:55:66
        """
        XCTAssertTrue(BluetoothActivityProvider.parseBatteries(from: output).isEmpty)
    }

    func testHandlesEmptyProfilerOutput() {
        XCTAssertTrue(BluetoothActivityProvider.parseBatteries(from: "").isEmpty)
    }

    // MARK: - Уведомления

    func testReadsBannerAsAppTitleAndBody() {
        let content = NotificationMirrorProvider.content(from: [
            "Telegram", "Никита", "привет, как дела?",
        ])

        XCTAssertEqual(content?.app, "Telegram")
        XCTAssertEqual(content?.title, "Никита")
        XCTAssertEqual(content?.body, "привет, как дела?")
    }

    func testBannerWithoutBodyIsStillValid() {
        let content = NotificationMirrorProvider.content(from: ["Календарь", "Через 10 минут"])
        XCTAssertEqual(content?.title, "Через 10 минут")
        XCTAssertNil(content?.body)
    }

    func testSkipsServiceLabelsAndTooShortBanners() {
        XCTAssertNil(NotificationMirrorProvider.content(from: ["Telegram"]),
                     "из одной строки уведомления не собрать")
        XCTAssertNil(NotificationMirrorProvider.content(from: ["Telegram", "  ", "Закрыть"]),
                     "служебные подписи не должны становиться заголовком")
    }

    func testJoinsMultilineBanner() {
        let content = NotificationMirrorProvider.content(from: [
            "Почта", "Тема письма", "первая строка", "вторая строка",
        ])
        XCTAssertEqual(content?.body, "первая строка вторая строка")
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
    /// Категория берётся из класса устройства, а не из названия: наушники
    /// могут называться как угодно.
    func testCategoryFromBluetoothClass() {
        XCTAssertEqual(
            BluetoothCategory.from(major: 0x04, minor: 0x06, name: "что угодно"),
            .headphones
        )
        XCTAssertEqual(
            BluetoothCategory.from(major: 0x04, minor: 0x05, name: "что угодно"),
            .speaker
        )
        XCTAssertEqual(BluetoothCategory.from(major: 0x02, minor: 0, name: "—"), .phone)
        XCTAssertEqual(BluetoothCategory.from(major: 0x07, minor: 0, name: "—"), .watch)
        XCTAssertEqual(BluetoothCategory.from(major: 0x05, minor: 0x10, name: "—"), .keyboard)
        XCTAssertEqual(BluetoothCategory.from(major: 0x05, minor: 0x20, name: "—"), .mouse)
    }

    func testCategoryFallsBackToNameWhenClassIsUnknown() {
        XCTAssertEqual(BluetoothCategory.from(major: 0, minor: 0, name: "AirPods (Мой)"), .headphones)
        XCTAssertEqual(BluetoothCategory.from(major: 0, minor: 0, name: "iPhone Никиты"), .phone)
        XCTAssertEqual(BluetoothCategory.from(major: 0, minor: 0, name: "Мои наушники"), .headphones)
        XCTAssertEqual(BluetoothCategory.from(major: 0, minor: 0, name: "Неизвестно"), .other)
    }

    func testEachCategoryHasItsOwnWording() {
        XCTAssertEqual(BluetoothCategory.headphones.connectedTitle, "Наушники подключены")
        XCTAssertEqual(BluetoothCategory.phone.connectedTitle, "Телефон рядом")
        XCTAssertNotEqual(BluetoothCategory.phone.symbol, BluetoothCategory.headphones.symbol)
    }

    /// Играющее приложение важнее системного посредника AirPlay.
    func testLocalAppWinsOverAirPlay() {
        let airplay = AudioProcessMonitor.Source(
            pid: 1, bundleID: "com.apple.AirPlayXPCHelper", name: "AirPlayXPCHelper"
        )
        let spotify = AudioProcessMonitor.Source(
            pid: 2, bundleID: "com.spotify.client", name: "Spotify"
        )

        XCTAssertTrue(airplay.isAirPlay)
        XCTAssertFalse(spotify.isAirPlay)
        XCTAssertEqual(AudioProcessMonitor.preferred(from: [airplay, spotify])?.name, "Spotify")
        XCTAssertEqual(AudioProcessMonitor.preferred(from: [airplay])?.name, "AirPlayXPCHelper")
    }
}
