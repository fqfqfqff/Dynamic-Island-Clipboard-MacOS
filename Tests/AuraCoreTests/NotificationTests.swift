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

    /// Незнакомому приложению рисуется свой значок из первой буквы — но он
    /// именно нарисованный, а не чужая иконка, подобранная нестрогим поиском.
    /// Среди запущенных всегда есть фоновые службы с пустым или странным
    /// именем, и раньше первая из них и становилась «иконкой» уведомления.
    func testUnknownAppGetsADrawnIconAndNotSomebodyElses() {
        let icon = NotificationMirrorProvider.icon(named: "такого приложения нет нигде")
        XCTAssertEqual(icon?.size, CGSize(width: 64, height: 64))
    }
}

/// Разбиение по разговорам и снятие прочитанного.
@MainActor
final class NotificationThreadTests: XCTestCase {
    private func makeProvider() -> NotificationMirrorProvider {
        let settings = SettingsStore(defaults: TestDefaults.make())
        return NotificationMirrorProvider(center: ActivityCenter(), settings: settings)
    }

    /// Пятеро написали — это пять дел, а не «5» на значке мессенджера.
    func testDifferentPeopleAreDifferentThreads() {
        let mother = NotificationMirrorProvider.threadKey(app: "Telegram", sender: "Мама")
        let boss = NotificationMirrorProvider.threadKey(app: "Telegram", sender: "Шеф")

        XCTAssertNotEqual(mother, boss)
        XCTAssertEqual(NotificationMirrorProvider.app(ofThread: mother), "Telegram")
        XCTAssertEqual(NotificationMirrorProvider.sender(ofThread: boss), "Шеф")
    }

    /// Имя и собеседник разделяются служебным символом: в именах людей
    /// встречается что угодно, включая точки, тире и вертикальную черту.
    func testSeparatorSurvivesAwkwardNames() {
        let key = NotificationMirrorProvider.threadKey(
            app: "Mail", sender: "ООО «Ромашка» | отдел продаж"
        )
        XCTAssertEqual(NotificationMirrorProvider.app(ofThread: key), "Mail")
        XCTAssertEqual(
            NotificationMirrorProvider.sender(ofThread: key),
            "ООО «Ромашка» | отдел продаж"
        )
    }

    func testActivityIDCarriesBothAppAndThread() {
        let key = NotificationMirrorProvider.threadKey(app: "Telegram", sender: "Мама")
        let id = "notification.\(key)"

        XCTAssertEqual(NotificationMirrorProvider.appName(fromActivityID: id), "Telegram")
        XCTAssertEqual(NotificationMirrorProvider.thread(fromActivityID: id), key)
        XCTAssertNil(NotificationMirrorProvider.thread(fromActivityID: "media.nowplaying"))
    }
}

/// Значок приложения должен быть у каждого уведомления.
@MainActor
final class NotificationMonogramTests: XCTestCase {
    /// Уведомления с айфона приходят от приложений, которых на Маке нет
    /// и быть не может. Пустое место в карточке — потеря: по значку
    /// и узнают, откуда пришло.
    func testUnknownAppStillGetsAnIcon() {
        let icon = NotificationMirrorProvider.icon(named: "Такого приложения нет нигде")
        XCTAssertNotNil(icon)
        XCTAssertEqual(icon?.size, CGSize(width: 64, height: 64))
    }

    /// Имя в баннере переведённое, а в `Info.plist` лежит английское.
    /// Перевод хранится отдельной таблицей внутри бандла, и без неё
    /// «Редактор скриптов» не находил сам «Script Editor» — уведомление
    /// оставалось с нарисованной буквой вместо иконки. Так было со всеми
    /// приложениями, у которых имя переводится: Почта, Сообщения, Фото.
    func testLocalizedAppNameFindsTheRealIcon() throws {
        // Список установленных приложений собирается в фоне — на главном
        // потоке он стоил бы секунды заминки на первом уведомлении.
        let ready = expectation(description: "список приложений собран")
        NotificationMirrorProvider.warmUp { ready.fulfill() }
        wait(for: [ready], timeout: 10)

        let icon = NotificationMirrorProvider.icon(named: "Редактор скриптов")
        try XCTSkipIf(icon == nil, "Редактора скриптов нет на этой машине")

        XCTAssertFalse(
            NotificationMirrorProvider.isMonogram(icon),
            "нашлась нарисованная буква, а не иконка приложения"
        )
    }

    func testSameNameKeepsTheSameLook() {
        let first = NotificationMirrorProvider.monogram(for: "Госуслуги")
        let second = NotificationMirrorProvider.monogram(for: "Госуслуги")
        XCTAssertTrue(first === second, "значок должен быть один и тот же, а не рисоваться заново")
    }

    func testEmptyNameHasNothingToDraw() {
        XCTAssertNil(NotificationMirrorProvider.monogram(for: "   "))
    }
}

/// Отсев повторов.
///
/// Событие «создано окно» приходит не на каждое уведомление: пока баннер
/// на экране, следующее сообщение система показывает в том же окне. Поэтому
/// содержимое перечитывается по таймеру — и без отсева остров дёргался бы
/// на каждом чтении.
final class NotificationRepeatTests: XCTestCase {
    private let now = Date()

    func testSameBannerReadAgainIsNotANewMessage() {
        let justShown = now.addingTimeInterval(-0.5)
        XCTAssertTrue(NotificationMirrorProvider.isRepeat(shownAt: justShown, now: now))
    }

    /// «ок» от того же человека через минуту — новое сообщение, а не тот же
    /// баннер. Без срока такие терялись бы совсем.
    func testSameTextLaterIsANewMessage() {
        let longAgo = now.addingTimeInterval(-NotificationMirrorProvider.repeatWindow - 1)
        XCTAssertFalse(NotificationMirrorProvider.isRepeat(shownAt: longAgo, now: now))
    }

    func testFirstTimeIsNeverARepeat() {
        XCTAssertFalse(NotificationMirrorProvider.isRepeat(shownAt: nil, now: now))
    }
}

/// Переключение рабочих столов тремя пальцами на доли секунды прячет строку
/// меню — и остров исчезал прямо посреди жеста вместе с уведомлением.
/// Признаку полноэкранного режима нужна выдержка.
@MainActor
final class FullScreenPatienceTests: XCTestCase {
    /// Первая же проверка не должна прятать остров: признак обязан
    /// продержаться. Жест переключения столов длится меньше выдержки.
    func testFirstSignDoesNotHideAnything() {
        let watcher = FullScreenWatcher()
        var changes: [Bool] = []
        watcher.onChange = { changes.append($0) }

        // Экран, у которого строка меню «спрятана»: видимая область
        // доходит до самого верха.
        watcher.start { FakeScreen.fullHeight }
        watcher.check()

        XCTAssertTrue(changes.isEmpty, "решение принято мгновенно, без выдержки")
        watcher.stop()
    }

    /// Выдержка должна перекрывать не только сам жест, но и Mission Control:
    /// пока он открыт, строка меню спрятана всё это время.
    func testPatienceCoversMissionControl() {
        XCTAssertGreaterThanOrEqual(FullScreenWatcher.patience, 1.5)
    }
}

/// Экран, у которого строка меню спрятана: видимая область во весь кадр.
private enum FakeScreen {
    static var fullHeight: NSScreen? { NSScreen.main }
}

/// Разбор файла с включёнными режимами фокусирования.
///
/// Записи лежат внутри `data`, а разбор искал их в корне — и режим
/// не определялся никогда. Проверялось это только на выключенном фокусе,
/// где ответ «выключен» совпадал случайно.
final class FocusAssertionsTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testModeInsideDataIsFound() {
        let file = data("""
        {"data":[{"storeAssertionRecords":[
          {"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.sleep.sleep-mode"}}
        ]}]}
        """)
        XCTAssertEqual(
            FocusActivityProvider.mode(fromAssertions: file),
            "com.apple.sleep.sleep-mode"
        )
    }

    /// Старая форма — записи прямо в корне — тоже должна читаться.
    func testModeInRootStillWorks() {
        let file = data("""
        {"storeAssertionRecords":[
          {"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}}
        ]}
        """)
        XCTAssertEqual(FocusActivityProvider.mode(fromAssertions: file), "com.apple.focus.work")
    }

    func testNoRecordsMeansNoFocus() {
        XCTAssertNil(FocusActivityProvider.mode(fromAssertions: data(#"{"data":[{}]}"#)))
        XCTAssertNil(FocusActivityProvider.mode(fromAssertions: data("{}")))
    }
}

/// Карточка и режим фокусирования.
final class FocusRuleTests: XCTestCase {
    func testCardBecomesBadgeWhileFocusIsOn() {
        XCTAssertEqual(
            NotificationMirrorProvider.rule("card", focusOn: true, respectFocus: true),
            "badge"
        )
    }

    func testFocusOffChangesNothing() {
        XCTAssertEqual(
            NotificationMirrorProvider.rule("card", focusOn: false, respectFocus: true),
            "card"
        )
    }

    /// Выключенная настройка — это выбор человека, и фокус её не отменяет.
    func testSettingOffKeepsTheCard() {
        XCTAssertEqual(
            NotificationMirrorProvider.rule("card", focusOn: true, respectFocus: false),
            "card"
        )
    }

    /// Приложение, которому выдали только значок, карточки и так не получало.
    func testBadgeStaysBadge() {
        XCTAssertEqual(
            NotificationMirrorProvider.rule("badge", focusOn: true, respectFocus: true),
            "badge"
        )
    }
}

/// Стопка уведомлений — это несколько сообщений в одном баннере.
///
/// Снято с живого экрана: система свернула четыре уведомления в одно,
/// подписала «стопкой» и сложила тексты подряд. Разобрать такое нельзя —
/// в карточку попадала каша из чужих обрывков.
final class StackedBannerTests: XCTestCase {
    private let stack = [
        "Редактор скриптов, Записка, чат, в журнал 23771, стопкой",
        "Записка", "чат", "в журнал 23771",
        "Telegram", "Вам новое сообщение", "15 минут назад",
    ]

    func testStackIsRecognised() {
        XCTAssertTrue(NotificationMirrorProvider.isStack(stack))
    }

    func testStackProducesNothing() {
        XCTAssertNil(NotificationMirrorProvider.content(from: ["Notification Center"] + stack))
    }

    /// Обычный баннер стопкой не считается — иначе пропадут все уведомления.
    func testOrdinaryBannerIsNotAStack() {
        let banner = ["Telegram, Мама, позвони", "Мама", "позвони"]
        XCTAssertFalse(NotificationMirrorProvider.isStack(banner))
        XCTAssertNotNil(NotificationMirrorProvider.content(from: ["Notification Center"] + banner))
    }
}
