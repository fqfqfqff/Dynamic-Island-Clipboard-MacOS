import AppKit
import XCTest
@testable import AuraCore

@MainActor
final class NotchViewModelTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1710, height: 1112)

    private func makeModel(expandOnHover: Bool = false) -> NotchViewModel {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.expandOnHover = expandOnHover

        let notch = CGRect(x: 750, y: screenFrame.maxY - 38, width: 209, height: 38)
        let geometry = NotchGeometry(
            notchRect: notch,
            menuBarHeight: 38,
            isPhysical: true,
            screenFrame: screenFrame
        )
        return NotchViewModel(geometry: geometry, settings: settings)
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
        model.expand()

        // чуть ниже панели, но рядом — панель должна остаться открытой
        model.handleMouseMoved(to: CGPoint(x: 855, y: screenFrame.maxY - 250))
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
    /// Регрессия: панель выше окна-контейнера выдавливало вверх, и её
    /// содержимое заезжало под вырез камеры.
    func testExpandedPanelFitsInsideWindow() {
        let model = makeModel()
        model.settings.expandedHeight = 480   // максимум, доступный в настройках
        model.expand()

        XCTAssertLessThanOrEqual(
            model.contentSize.height,
            NotchViewModel.windowSize.height,
            "панель обязана помещаться в окно целиком"
        )
        XCTAssertLessThanOrEqual(model.contentSize.width, NotchViewModel.windowSize.width)
    }

    func testInteractiveRectFitsWindowWhenExpanded() {
        let model = makeModel()
        model.settings.expandedHeight = 480
        model.expand()

        let rect = model.interactiveRectInWindow
        XCTAssertGreaterThanOrEqual(rect.minY, 0, "зона клика не должна уходить за окно")
        XCTAssertEqual(rect.maxY, NotchViewModel.windowSize.height, accuracy: 0.001)
    }
}

extension NotchViewModelTests {
    /// Регрессия: панель, которую сжали ниже её содержимого, выдавливала
    /// обложку вверх — прямо под вырез камеры.
    func testExpandedPanelNeverShorterThanItsContent() {
        let model = makeModel()
        model.settings.expandedHeight = 120   // заведомо мало

        model.expand()

        let required = 38 + NotchViewModel.contentTopInset + model.playerContentHeight
        XCTAssertGreaterThanOrEqual(model.contentSize.height, required,
                                    "содержимое плеера обязано помещаться целиком")
    }

    func testGenerousHeightIsRespected() {
        let model = makeModel()
        model.settings.expandedHeight = 460
        model.expand()
        XCTAssertEqual(model.contentSize.height, 460, accuracy: 0.001)
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
