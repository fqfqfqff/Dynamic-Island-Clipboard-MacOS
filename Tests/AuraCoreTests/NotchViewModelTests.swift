import AppKit
import XCTest
@testable import AuraCore

@MainActor
final class NotchViewModelTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1710, height: 1112)

    private func makeModel(
        expandOnHover: Bool = false,
        hasContent: Bool = true
    ) -> NotchViewModel {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.expandOnHover = expandOnHover

        let notch = CGRect(x: 750, y: screenFrame.maxY - 38, width: 209, height: 38)
        let geometry = NotchGeometry(
            notchRect: notch,
            menuBarHeight: 38,
            isPhysical: true,
            screenFrame: screenFrame
        )
        let model = NotchViewModel(geometry: geometry, settings: settings)
        model.hasContent = hasContent
        return model
    }

    func testCollapsedMatchesPhysicalNotchExactly() {
        let model = makeModel()
        XCTAssertEqual(model.contentSize, CGSize(width: 209, height: 38),
                       "без активностей вырез обязан совпадать с физическим, иначе он заметен")
    }

    func testActivityWidensNotchBySlots() {
        let model = makeModel()
        model.compactAccessoryWidth = 88
        XCTAssertEqual(model.contentSize.width, 209 + 88)
        XCTAssertEqual(model.contentSize.height, 38, "по высоте вырез расти не должен")
    }

    func testExpandedIsAtLeastNotchWidthPlusMargin() {
        let model = makeModel()
        model.settings.expandedWidth = 100   // заведомо меньше выреза
        model.expand()
        XCTAssertGreaterThanOrEqual(model.contentSize.width, 209 + 80,
                                    "панель уже выреза выглядела бы обрубленной")
    }

    func testInteractiveRectStaysInsideWindowAndHugsTop() {
        let model = makeModel()
        let rect = model.interactiveRectInWindow
        let window = NotchViewModel.windowSize

        XCTAssertEqual(rect.maxY, window.height, accuracy: 0.001, "зона должна прилегать к верху окна")
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertLessThanOrEqual(rect.maxX, window.width)
        XCTAssertEqual(rect.midX, window.width / 2, accuracy: 0.001)
    }

    func testHoverGrowsAndLeavingCollapses() {
        let model = makeModel()
        let inside = CGPoint(x: 850, y: screenFrame.maxY - 10)

        model.handleMouseMoved(to: inside)
        XCTAssertEqual(model.state, .peek)

        model.handleMouseMoved(to: CGPoint(x: 100, y: 400))
        XCTAssertEqual(model.state, .collapsed)
    }

    func testHoverOpensPanelWhenSettingIsOn() {
        let model = makeModel(expandOnHover: true)
        model.handleMouseMoved(to: CGPoint(x: 850, y: screenFrame.maxY - 10))
        XCTAssertEqual(model.state, .expanded)
    }

    func testExpandedSurvivesSmallMouseDrift() {
        let model = makeModel()
        model.hasMedia = true
        model.expand()

        // Чуть ниже панели, но рядом — она должна остаться открытой.
        // Точка считается от её настоящей высоты: панель теперь ровно
        // по содержимому, и фиксированное число здесь врало бы.
        let justBelow = screenFrame.maxY - model.contentSize.height - 20
        model.handleMouseMoved(to: CGPoint(x: 855, y: justBelow))
        XCTAssertEqual(model.state, .expanded)

        model.handleMouseMoved(to: CGPoint(x: 200, y: 100))
        XCTAssertEqual(model.state, .collapsed)
    }

    func testToggleAndCollapse() {
        let model = makeModel()
        model.toggleExpanded()
        XCTAssertEqual(model.state, .expanded)
        model.toggleExpanded()
        XCTAssertEqual(model.state, .collapsed)
    }

    // MARK: - Пустой остров

    /// Раскрывать нечего — значит, и раскрывать незачем: панель без
    /// содержимого это чёрный прямоугольник посреди экрана.
    func testHoverOnlyGrowsWhenThereIsNothingToShow() {
        let model = makeModel(expandOnHover: true, hasContent: false)
        model.handleMouseMoved(to: CGPoint(x: 850, y: screenFrame.maxY - 10))
        XCTAssertEqual(model.state, .peek)
    }

    func testTapDoesNotOpenEmptyPanel() {
        let model = makeModel(hasContent: false)
        model.toggleExpanded()
        XCTAssertEqual(model.state, .peek)
    }

    /// Программное раскрытие правилу не подчиняется: файл, который тащат
    /// на вырез, обязан увидеть, куда его бросают.
    func testProgrammaticExpandIgnoresEmptiness() {
        let model = makeModel(hasContent: false)
        model.expand()
        XCTAssertEqual(model.state, .expanded)
    }

    // MARK: - Мёртвая зона наведения

    /// Регрессия, которая ломала наведение годами.
    ///
    /// Окно перехватывает мышь по всей видимой форме — вырез плюс компактные
    /// слоты. Открывался остров по зоне вокруг голого выреза, которая уже.
    /// Курсор, попавший в разницу, замораживал остров: мышь уже наша, а
    /// открытия нет, и событий движения больше неоткуда взять.
    func testHoverZoneCoversEverythingTheWindowGrabs() {
        let model = makeModel()
        model.compactAccessoryWidth = 88

        let grabbed = model.interactiveRectOnScreen
        XCTAssertTrue(
            model.hoverRectOnScreen.contains(CGPoint(x: grabbed.minX + 1, y: grabbed.midY)),
            "левый компактный слот перехватывает мышь, но не открывает остров"
        )
        XCTAssertTrue(
            model.hoverRectOnScreen.contains(CGPoint(x: grabbed.maxX - 1, y: grabbed.midY)),
            "правый компактный слот перехватывает мышь, но не открывает остров"
        )
    }

    /// Наведение на компактный слот обязано открывать остров, а не молчать.
    func testHoverOverAccessorySlotOpensIsland() {
        let model = makeModel(expandOnHover: true)
        model.compactAccessoryWidth = 88

        let slot = CGPoint(
            x: model.interactiveRectOnScreen.minX + 4,
            y: screenFrame.maxY - 10
        )
        model.handleMouseMoved(to: slot)
        XCTAssertEqual(model.state, .expanded)
    }
}

extension NotchViewModelTests {
    /// Регрессия: панель шире выреза, и если считать зоной всё окно, она
    /// перекрывает строку меню — вместе с иконками приложений в ней.
    func testCollapsedInteractiveZoneCoversOnlyTheNotch() {
        let model = makeModel()
        let zone = model.interactiveRectOnScreen

        XCTAssertEqual(zone.width, 209, "в покое кликабелен только сам вырез")
        XCTAssertEqual(zone.height, 38)
        XCTAssertEqual(zone.maxY, screenFrame.maxY, accuracy: 0.001)

        // Правый верхний угол экрана — там живут иконки строки меню.
        let statusIconArea = CGPoint(x: screenFrame.maxX - 60, y: screenFrame.maxY - 12)
        XCTAssertFalse(zone.contains(statusIconArea),
                       "иконки в строке меню обязаны оставаться доступными")

        // Левый верхний угол — меню приложения.
        XCTAssertFalse(zone.contains(CGPoint(x: 40, y: screenFrame.maxY - 12)))
    }

    func testExpandedZoneStillLeavesStatusIconsAlone() {
        let model = makeModel()
        model.expand()
        let zone = model.interactiveRectOnScreen

        XCTAssertFalse(zone.contains(CGPoint(x: screenFrame.maxX - 60, y: screenFrame.maxY - 12)))
        XCTAssertTrue(zone.contains(CGPoint(x: screenFrame.midX, y: screenFrame.maxY - 20)),
                      "сама панель кликабельной остаться должна")
    }
}

extension NotchViewModelTests {
    /// Панель под завязку — плеер, полка и полный список — обязана помещаться
    /// в окно целиком: иначе её выдавливает вверх и содержимое заезжает
    /// под вырез камеры.
    private func fullModel() -> NotchViewModel {
        let model = makeModel()
        model.hasMedia = true
        model.hasShelf = true
        model.extraRowCount = 9   // заведомо больше, чем панель показывает
        model.expand()
        return model
    }

    func testExpandedPanelFitsInsideWindow() {
        let model = fullModel()
        XCTAssertLessThanOrEqual(
            model.contentSize.height,
            NotchViewModel.windowSize.height,
            "панель обязана помещаться в окно целиком"
        )
        XCTAssertLessThanOrEqual(model.contentSize.width, NotchViewModel.windowSize.width)
    }

    /// Окно под раскрытую панель теперь по размеру самой панели, а не
    /// всегда 720×560: прозрачное окно система пересобирает целиком, и
    /// площадь платится на каждом кадре. Панель обязана в него помещаться
    /// при любом содержимом — иначе она обрежется по краю окна.
    func testPanelAlwaysFitsItsWindow() {
        for rows in [0, 1, 3, 9] {
            for media in [false, true] {
                let model = makeModel()
                model.hasMedia = media
                model.hasShelf = true
                model.extraRowCount = rows
                model.expand()

                let window = model.expandedWindowSize
                XCTAssertGreaterThanOrEqual(
                    window.width, model.contentSize.width,
                    "панель шире своего окна: строк \(rows), плеер \(media)"
                )
                XCTAssertGreaterThanOrEqual(
                    window.height, model.contentSize.height,
                    "панель выше своего окна: строк \(rows), плеер \(media)"
                )
                XCTAssertLessThanOrEqual(window.width, NotchViewModel.windowSize.width)
                XCTAssertLessThanOrEqual(window.height, NotchViewModel.windowSize.height)
            }
        }
    }

    func testInteractiveRectFitsWindowWhenExpanded() {
        let model = fullModel()
        let rect = model.interactiveRectInWindow
        XCTAssertGreaterThanOrEqual(rect.minY, 0, "зона клика не должна уходить за окно")
        XCTAssertEqual(rect.maxY, NotchViewModel.windowSize.height, accuracy: 0.001)
    }
}

extension NotchViewModelTests {
    /// Регрессия: панель короче своего содержимого выдавливала обложку
    /// вверх — прямо под вырез камеры.
    func testExpandedPanelNeverShorterThanItsContent() {
        let model = makeModel()
        model.hasMedia = true
        model.expand()

        let required = 38 + NotchViewModel.contentTopInset + model.playerContentHeight
        XCTAssertGreaterThanOrEqual(model.contentSize.height, required,
                                    "содержимое плеера обязано помещаться целиком")
    }

    // MARK: - Панель по содержимому

    /// Панель фиксированной высоты без музыки была чёрным прямоугольником
    /// в треть экрана, наполовину пустым.
    func testPanelWithoutMediaIsMuchShorterThanWithIt() {
        let empty = makeModel()
        empty.extraRowCount = 1
        empty.expand()

        let withMedia = makeModel()
        withMedia.hasMedia = true
        withMedia.extraRowCount = 1
        withMedia.expand()

        XCTAssertLessThan(
            empty.contentSize.height,
            withMedia.contentSize.height - 100,
            "без плеера панель обязана быть заметно ниже, а не такой же"
        )
    }

    /// Панель растёт под каждую строку: прокрутка внутри выреза — плохой
    /// обмен, ради неё пришлось бы уже смотреть в панель.
    func testEveryRowAddsHeight() {
        func height(rows: Int) -> CGFloat {
            let model = makeModel()
            model.extraRowCount = rows
            model.expand()
            return model.contentSize.height
        }

        for rows in 1..<5 {
            XCTAssertGreaterThan(
                height(rows: rows + 1), height(rows: rows),
                "строка \(rows + 1) не добавила высоты — список начнёт листаться"
            )
        }
        // Сверху всё равно есть предел: панель не может быть выше окна.
        XCTAssertLessThanOrEqual(height(rows: 40), NotchViewModel.windowSize.height)
    }
}

extension NotchViewModelTests {
    /// Остров должен подрастать заранее, по мере приближения курсора,
    /// а не скачком в момент пересечения границы.
    func testProximityGrowsAsCursorApproaches() {
        let model = makeModel()
        let notchCenter = CGPoint(x: 855, y: screenFrame.maxY - 19)

        model.handleMouseMoved(to: CGPoint(x: notchCenter.x, y: notchCenter.y - 400))
        XCTAssertEqual(model.proximity, 0, "издалека реакции быть не должно")

        model.handleMouseMoved(to: CGPoint(x: notchCenter.x, y: notchCenter.y - 120))
        let far = model.proximity

        model.handleMouseMoved(to: CGPoint(x: notchCenter.x, y: notchCenter.y - 40))
        let near = model.proximity

        XCTAssertGreaterThan(far, 0)
        XCTAssertGreaterThan(near, far, "ближе — заметнее")
        XCTAssertLessThanOrEqual(near, 1)
    }

    func testProximityStaysZeroWhenDisabled() {
        let model = makeModel()
        model.settings.reactToProximity = false

        model.handleMouseMoved(to: CGPoint(x: 855, y: screenFrame.maxY - 25))
        XCTAssertEqual(model.proximity, 0)
    }

    /// Размер свёрнутого выреза без активностей и без курсора рядом обязан
    /// точно совпадать с физическим — иначе он становится заметен.
    func testProximityDoesNotChangeRestingSize() {
        let model = makeModel()
        model.handleMouseMoved(to: CGPoint(x: 100, y: 100))
        XCTAssertEqual(model.contentSize, CGSize(width: 209, height: 38))
    }
}
