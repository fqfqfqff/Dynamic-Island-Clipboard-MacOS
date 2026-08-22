import XCTest
@testable import AuraCore

/// Разбор баннера уведомления. Читать его приходится через Универсальный
/// доступ, то есть по текстовым узлам чужого окна, — и всё, что там лежит,
/// нужно разложить самим.
final class NotificationTests: XCTestCase {

    // MARK: - Из чего состоит баннер

    /// Снято с живого баннера macOS 26. Имя приложения есть только в сводке,
    /// первым элементом до запятой; отдельного узла с ним нет, а первый узел
    /// окна — это его заголовок, «Notification Center».
    ///
    /// Раньше приложением считался именно он. Отсюда разом три поломки:
    /// не было иконки, цвет откатывался к запасному, и уведомление никогда
    /// не помечалось прочитанным — сверять было не с чем.
    func testRealBannerFromMacOS() {
        let content = NotificationMirrorProvider.content(from: [
            "Notification Center",
            "Редактор скриптов, Никита Соловьёв, рабочий чат, привет, посмотри пулреквест",
            "Никита Соловьёв",
            "рабочий чат",
            "привет, посмотри пулреквест",
        ])

        XCTAssertEqual(content?.app, "Редактор скриптов")
        XCTAssertEqual(content?.sender, "Никита Соловьёв")
        XCTAssertEqual(content?.body, "рабочий чат · привет, посмотри пулреквест")
    }

    func testWindowTitleIsNeverMistakenForTheApp() {
        let content = NotificationMirrorProvider.content(from: [
            "Центр уведомлений", "Telegram, Мама, позвони", "Мама", "позвони",
        ])
        XCTAssertEqual(content?.app, "Telegram")
    }

    /// Кнопки баннера — такие же текстовые узлы, и без отсева они приезжают
    /// в текст сообщения.
    func testButtonsDoNotLeakIntoTheMessage() {
        let content = NotificationMirrorProvider.content(
            from: ["Telegram", "Мама", "позвони", "Ответить", "Закрыть"]
        )
        XCTAssertEqual(content?.body, "позвони")
    }

    // MARK: - Что именно прислали

    /// Мессенджер не кладёт в баннер вложение — он пишет его название словами.
    func testAttachmentKindIsReadFromWording() {
        XCTAssertEqual(NotificationMirrorProvider.kind(from: "Голосовое сообщение"), .voice)
        XCTAssertEqual(NotificationMirrorProvider.kind(from: "Voice message"), .voice)
        XCTAssertEqual(NotificationMirrorProvider.kind(from: "Видеосообщение"), .videoMessage)
        XCTAssertEqual(NotificationMirrorProvider.kind(from: "Фотография"), .photo)
        XCTAssertEqual(NotificationMirrorProvider.kind(from: "Стикер"), .sticker)
        XCTAssertEqual(NotificationMirrorProvider.kind(from: "Файл"), .file)
        XCTAssertEqual(NotificationMirrorProvider.kind(from: "Входящий звонок"), .call)
    }

    /// Слово-маркер внутри обычной фразы — это обычная фраза.
    func testWordInsideASentenceIsStillJustText() {
        XCTAssertEqual(NotificationMirrorProvider.kind(from: "посмотри это видео вечером"), .text)
        XCTAssertEqual(NotificationMirrorProvider.kind(from: "скинь фото с дачи"), .text)
        XCTAssertEqual(NotificationMirrorProvider.kind(from: nil), .text)
        XCTAssertEqual(NotificationMirrorProvider.kind(from: ""), .text)
    }

    func testEveryKindHasItsOwnSymbol() {
        let kinds: [NotificationMirrorProvider.Message.Kind] =
            [.text, .voice, .videoMessage, .photo, .video, .sticker, .file, .call]
        XCTAssertEqual(Set(kinds.map(\.symbol)).count, kinds.count,
                       "одинаковые значки не дадут различить тип боковым зрением")
    }
}

/// Переключатель языка меняет бандл строк на лету — без перезапуска.
final class InterfaceLanguageTests: XCTestCase {
    override func tearDown() {
        Localization.language = "system"
        super.tearDown()
    }

    func testLanguageSwitchChangesStrings() {
        Localization.language = "ru"
        let russian = t("ui.7d4e9a02", "Режим модема")

        Localization.language = "en"
        let english = t("ui.7d4e9a02", "Режим модема")

        XCTAssertEqual(russian, "Режим модема")
        XCTAssertEqual(english, "Personal Hotspot")
    }

    func testUnknownKeyFallsBackInAnyLanguage() {
        for language in ["system", "ru", "en"] {
            Localization.language = language
            XCTAssertEqual(t("ui.нет-такого", "запасной"), "запасной")
        }
    }
}

/// Уведомления с айфона приходят от приложений, которых на Маке может
/// не быть запущено вовсе. Иконку нужно искать и среди установленных.
@MainActor
final class NotificationIconTests: XCTestCase {
    func testFindsIconOfAnAppThatIsNotRunning() throws {
        // Системные приложения есть на любой машине, но запущены далеко
        // не всегда — на них и проверяем.
        let candidates = ["Калькулятор", "Calculator", "Шахматы", "Chess"]
        let found = candidates.compactMap { NotificationMirrorProvider.icon(named: $0) }

        XCTAssertFalse(found.isEmpty, "не нашлось ни одного установленного приложения")
    }

    func testUnknownAppHasNoIcon() {
        XCTAssertNil(NotificationMirrorProvider.icon(named: "такого приложения нет нигде"))
    }
}
