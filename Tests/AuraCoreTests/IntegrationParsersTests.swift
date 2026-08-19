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
