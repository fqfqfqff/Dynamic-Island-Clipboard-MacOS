import SwiftUI
import AppKit
import Combine

/// Состояние выреза. Переходы: collapsed ⇄ peek → event → expanded.
enum NotchState: Equatable {
    /// Незаметная чёрная пилюля ровно по форме выреза.
    case collapsed
    /// Курсор рядом — вырез слегка подрос и намекает, что на него можно нажать.
    case peek
    /// Событие: вырез вырастает сверху вниз на одну строку и показывает,
    /// что произошло. Не панель — карточка ровно по содержимому, как на iPhone.
    case event
    /// Раскрытая панель с содержимым.
    case expanded

    /// Насколько состояние «больше» предыдущего — по этому выбирается
    /// анимация: раскрытие или сворачивание.
    var rank: Int {
        switch self {
        case .collapsed: 0
        case .peek: 1
        case .event: 2
        case .expanded: 3
        }
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var state: NotchState = .collapsed
    @Published var geometry: NotchGeometry

    /// Суммарная ширина компактных слотов слева и справа от выреза.
    /// Ноль — активностей нет, и вырез неотличим от физического.
    @Published var compactAccessoryWidth: CGFloat = 0

    /// Есть ли шапка со счётчиком непрочитанного и баннер отказа в доступе.
    ///
    /// Панель считает высоту заранее, а не измеряет: измерение здесь
    /// замкнуто само на себя — высота содержимого ограничена высотой панели,
    /// которая считается от высоты содержимого. Поэтому расчёт обязан знать
    /// про всё, что в панели бывает, а разметка — держать эти высоты
    /// постоянными. Числа лежат в `ActivitiesPane`.
    @Published var hasNotificationHeader = false
    @Published var hasAccessBanner = false

    /// Играет ли что-нибудь: от этого зависит, нужна ли панели высота
    /// под карточку плеера.
    @Published var hasMedia = false
    /// Лежит ли что-то на полке.
    @Published var hasShelf = false

    /// Сколько активностей, кроме плеера, ждут показа в раскрытой панели.
    ///
    /// Панель фиксированной высоты целиком уходила под карточку плеера, и
    /// список под ней сжимался в несколько точек: уведомление, зарядка и
    /// прогресс сборки просто не показывались, хотя значок в вырезе горел.
    @Published var extraRowCount: Int = 0

    /// Есть ли что показывать в раскрытой панели.
    ///
    /// Пустая панель — это чёрный прямоугольник посреди экрана и больше
    /// ничего, поэтому по наведению она не раскрывается: остров лишь слегка
    /// подрастает. Программное раскрытие (`expand()`, файл на вырезе,
    /// `aura open`) флагом не ограничено — там пользователь знает, что делает.
    @Published var hasContent = false

    /// Насколько курсор близок к вырезу: 0 — далеко, 1 — прямо над ним.
    /// Остров подрастает плавно вслед за приближением, а не скачком в момент
    /// пересечения границы.
    @Published var proximity: CGFloat = 0

    let settings: SettingsStore

    /// Ширина одного компактного слота.
    var accessorySlotWidth: CGFloat { settings.accessorySlotWidth }

    /// Размер окна-контейнера. Постоянный: анимируем содержимое, а не окно —
    /// ресайз NSWindow на каждом кадре заметно дёргается.
    ///
    /// Высота с запасом: панель, не помещавшаяся в окно, выдавливалась вверх и
    /// заезжала под вырез камеры.
    static let windowSize = CGSize(width: 720, height: 720)

    /// Выше этого панель не растёт.
    ///
    /// Не равно высоте окна: под тенью и под запасом на промах курсора
    /// у нижней кромки должно оставаться место, иначе они срезаются
    /// краем окна вместе с последней строкой списка.
    static let maxPanelHeight: CGFloat = 620

    /// Сколько окна нужно под раскрытую панель.
    ///
    /// Не `windowSize`: прозрачное окно поверх всего система пересобирает
    /// целиком на каждой перерисовке, и площадь здесь платится напрямую.
    /// Панель шириной в триста точек не нуждается в окне на семьсот — это
    /// впятеро больше пикселей на каждый кадр полоски или полосы времени.
    ///
    /// Запас по краям — под тень и под то, чтобы клик у самой кромки
    /// не проваливался.
    var expandedWindowSize: CGSize {
        let panel = expandedSize
        // Карточка уведомления бывает шире раскрытой панели, а окно у них
        // общее. Мерить только по панели значит обрезать карточку по бокам
        // вместе со свечением обводки — ровно это и было видно как
        // «срезанные края».
        let widest = max(panel.width, eventSize.width)
        let tallest = max(panel.height, eventSize.height)

        return CGSize(
            width: min(Self.windowSize.width, max(compactWindowWidth, widest + 120)),
            height: min(Self.windowSize.height, tallest + 90)
        )
    }

    /// Ширина окна в покое: вырез, слоты и запас на подсказку.
    var compactWindowWidth: CGFloat {
        geometry.notchSize.width + accessorySlotWidth * 2 + 120
    }

    /// Размер раскрытой панели.
    /// Высота содержимого плеера под текущие настройки: обложка, текст,
    /// полоса длительности и кнопки вместе с отступами.
    var playerContentHeight: CGFloat {
        var height = settings.artworkSize + 6      // обложка и отступ под ней
        height += settings.titleFontSize + 16      // название и исполнитель
        if settings.showSeekBar { height += 32 }
        if settings.showControls { height += 40 }
        return height + 12
    }

    /// Отступ содержимого от нижней кромки выреза. Задаётся здесь, а не в виде,
    /// чтобы высота панели считалась от того же числа, от которого содержимое
    /// отрисовывается.
    static let contentTopInset: CGFloat = 12

    /// Размер карточки события.
    ///
    /// Это не панель: вырез вырастает ровно настолько, чтобы поместились
    /// иконка приложения, две строки текста и значок типа сообщения.
    var eventSize: CGSize {
        let scale = CGFloat(settings.notificationScale)
        return CGSize(
            width: max(360 * scale, geometry.notchSize.width + 150 * scale),
            height: geometry.menuBarHeight + 56 * scale
        )
    }

    /// Панель растёт под все строки, а не под три.
    ///
    /// Прокрутка внутри выреза — плохой обмен: чтобы её увидеть, нужно уже
    /// смотреть в панель, а смысл острова в том, чтобы всё было видно сразу.
    /// Очередь активностей и так ограничена сверху, поэтому предел здесь
    /// заведомо выше — он лишь страховка от бесконечного роста.
    private static let maxVisibleRows = 6
    /// Высота полки с файлами.
    private static let shelfHeight: CGFloat = 78
    /// Зазор между блоками и отступ снизу.
    private static let blockSpacing: CGFloat = 8
    private static let bottomPadding: CGFloat = 10

    /// Размер раскрытой панели — ровно по тому, что в ней лежит.
    ///
    /// Раньше высота бралась из настройки и была одинаковой всегда. Без музыки
    /// это означало чёрный прямоугольник в треть экрана, наполовину пустой;
    /// с музыкой и списком — наоборот, список не помещался. Панель обязана
    /// быть ровно такой, сколько в ней содержимого.
    var expandedSize: CGSize {
        var height = geometry.menuBarHeight + Self.contentTopInset
        var blocks = 0

        if hasAccessBanner {
            height += ActivitiesPane.bannerHeight
            blocks += 1
        }
        if hasMedia {
            height += playerContentHeight
            blocks += 1
        }
        if hasShelf {
            height += Self.shelfHeight
            blocks += 1
        }
        if hasNotificationHeader {
            height += ActivitiesPane.headerHeight
            blocks += 1
        }

        let rows = min(extraRowCount, Self.maxVisibleRows)
        if rows > 0 {
            // Строки идут своим стеком с зазором в шесть точек между ними.
            height += CGFloat(rows) * ActivitiesPane.rowHeight
                + CGFloat(max(0, rows - 1)) * 6
            blocks += 1
        }

        // Зазоры считаются по промежуткам, а не по блокам: у одного блока
        // соседа нет, и лишняя пустота внизу заметна.
        height += CGFloat(max(0, blocks - 1)) * Self.blockSpacing
        height += Self.bottomPadding

        return CGSize(
            width: settings.expandedWidth,
            height: min(max(height, Self.minimumPanelHeight), Self.maxPanelHeight)
        )
    }

    /// Ниже этого панель не сжимается: совсем плоская она читается как сбой,
    /// а не как панель.
    private static let minimumPanelHeight: CGFloat = 96

    init(geometry: NotchGeometry, settings: SettingsStore) {
        self.geometry = geometry
        self.settings = settings
    }

    /// Размер видимой чёрной формы для текущего состояния.
    var contentSize: CGSize {
        let notch = geometry.notchSize
        switch state {
        case .collapsed:
            // Подрастание на подлёте: максимум четыре точки, этого хватает,
            // чтобы движение читалось, и мало, чтобы мешать.
            // Только по высоте: тот же принцип, что и у `peek`. Ширина
            // выреза — физическая величина, и всё, что её трогает,
            // читается как рывок вбок.
            let lift = settings.reactToProximity ? proximity * 4 : 0
            return CGSize(
                width: notch.width + compactAccessoryWidth,
                height: notch.height + lift
            )
        case .peek:
            // Растём только вниз.
            //
            // Раньше остров при наведении прибавлял ещё и 28 точек ширины.
            // Расширение вбок шло одновременно с появлением подсказки, и глаз
            // читал это как движение по диагонали — подсказка будто выезжала
            // сбоку. Настоящий вырез вширь не меняется; меняться может только
            // то, что из-под него выходит.
            return CGSize(
                width: notch.width + compactAccessoryWidth,
                height: notch.height + settings.peekGrowth
            )
        case .event:
            return eventSize
        case .expanded:
            return CGSize(
                width: max(expandedSize.width, notch.width + 80),
                height: expandedSize.height
            )
        }
    }

    /// Зона, в которой окно перехватывает клики. Всё остальное прозрачно для
    /// мыши, иначе панель накрыла бы строку меню целиком.
    /// Фактический размер окна — он меняется вместе с состоянием, поэтому
    /// зону клика нельзя считать от постоянной величины.
    @Published var currentWindowSize: CGSize = NotchViewModel.windowSize

    var interactiveRectInWindow: CGRect {
        let size = contentSize
        return CGRect(
            x: (currentWindowSize.width - size.width) / 2,
            y: currentWindowSize.height - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Видимая форма панели в координатах экрана. По ней решается, должно ли
    /// окно вообще принимать клики: всё остальное время оно обязано быть
    /// прозрачным для мыши, иначе перекрывает строку меню.
    var interactiveRectOnScreen: CGRect {
        let size = contentSize
        return CGRect(
            x: geometry.notchRect.midX - size.width / 2,
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Зона притяжения курсора в глобальных координатах.
    ///
    /// Считается от видимой формы, а не от голого выреза, и это принципиально.
    /// Раньше окно забирало мышь по всей форме — вырез плюс компактные слоты,
    /// до 88 точек лишней ширины, — а открывалось только по вырезу плюс 18.
    /// Между ними получалось кольцо, где мышь уже наша, но открытия ещё нет.
    /// Курсор, попавший туда, замораживал остров: событий движения больше
    /// не приходило ни от глобального монитора (события ушли «нам»), ни от
    /// панели (окно не key и не принимает mouseMoved). Отсюда и знаменитое
    /// «открывается только со второго раза».
    var hoverRectOnScreen: CGRect {
        interactiveRectOnScreen.insetBy(dx: -18, dy: -6)
    }

    /// Зона, при выходе из которой подсказка гаснет. Она заметно шире зоны
    /// входа: без этого запаса вырез мигал, когда курсор шёл вдоль кромки.
    var hoverExitRectOnScreen: CGRect {
        interactiveRectOnScreen.insetBy(dx: -40, dy: -22)
    }

    /// Расстояние от курсора до выреза, приведённое к 0…1.
    private func proximityValue(for point: CGPoint) -> CGFloat {
        let rect = geometry.notchRect
        let dx = max(0, max(rect.minX - point.x, point.x - rect.maxX))
        let dy = max(0, max(rect.minY - point.y, point.y - rect.maxY))
        let distance = hypot(dx, dy)

        let reach = CGFloat(settings.proximityReach)
        guard distance < reach else { return 0 }
        // Квадратичное нарастание: вдали почти не заметно, у самого выреза
        // растёт быстро.
        let linear = 1 - distance / reach
        return linear * linear
    }

    func handleMouseMoved(to point: CGPoint, speed: CGFloat = 0) {
        if settings.reactToProximity {
            let next = proximityValue(for: point)
            // Порог крупнее: близость публикуется двадцать раз в секунду,
            // и каждая публикация — это пересчёт тела всего острова.
            if abs(next - proximity) > 0.05 {
                // Та же пружина, что у смены состояния: близость двигает
                // ту же высоту острова, и вторая кривая на ней читается
                // как дрожание на подлёте курсора.
                withAnimation(AuraAnimation.accessory(settings: settings)) {
                    proximity = next
                }
            }
        } else if proximity != 0 {
            proximity = 0
        }

        lastSpeed = speed
        handleStateChange(at: point)
    }

    private var lastSpeed: CGFloat = 0

    /// Длительность перехода зависит от того, как быстро движется курсор:
    /// на резком движении остров должен успеть за рукой, на медленном —
    /// открываться степенно.
    private func animation(shrinking: Bool) -> Animation {
        let damping = AuraAnimation.damping(settings)

        guard settings.reactToProximity else {
            return .spring(
                response: (shrinking ? 0.52 : 0.42) * settings.animationSpeed,
                dampingFraction: shrinking ? min(0.97, damping + 0.05) : damping
            )
        }

        // Скорость курсора подтягивает длительность, но не схлопывает её:
        // даже самое резкое движение оставляет анимацию видимой.
        let normalized = min(1, lastSpeed / 2200)
        let base = shrinking ? 0.55 : 0.44
        let fastest = shrinking ? 0.42 : 0.32
        let response = (base - (base - fastest) * Double(normalized)) * settings.animationSpeed

        return .spring(
            response: response,
            dampingFraction: shrinking ? min(0.97, damping + 0.05) : damping
        )
    }

    private func handleStateChange(at point: CGPoint) {
        switch state {
        case .collapsed:
            if hoverRectOnScreen.contains(point) {
                scheduleHoverOpen()
            } else {
                hoverWork?.cancel()
                hoverWork = nil
            }
        case .peek:
            if !hoverExitRectOnScreen.contains(point) { transition(to: .collapsed) }
        case .event:
            // Событие живёт по своему таймеру, а не по курсору: уведомление,
            // исчезающее от того, что мышь уехала, — это потерянное
            // уведомление. Наведение на него раскрывает панель целиком.
            if hoverRectOnScreen.contains(point), settings.expandOnHover, hasContent {
                transition(to: .expanded)
            }
        case .expanded:
            // Раскрытую панель закрываем, только если курсор ушёл заметно далеко.
            let size = contentSize
            let panel = CGRect(
                x: geometry.notchRect.midX - size.width / 2,
                y: geometry.screenFrame.maxY - size.height,
                width: size.width,
                height: size.height
            ).insetBy(dx: -40, dy: -40)
            if !panel.contains(point) { transition(to: .collapsed) }
        }
    }

    private var hoverWork: DispatchWorkItem?
    private var autoCollapseWork: DispatchWorkItem?
    private var eventWork: DispatchWorkItem?

    /// Показать событие: вырез вырастает сверху вниз и держится заданное
    /// время. `hold` в ноль означает «пока не уберут руками» — так работает
    /// режим «держать до прочтения».
    func presentEvent(hold: TimeInterval) {
        eventWork?.cancel()
        eventWork = nil

        // Раскрытую панель уведомление не сворачивает: пользователь в ней
        // что-то делает, и подменять её карточкой невежливо.
        guard state != .expanded else { return }
        transition(to: .event)

        guard hold > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.state == .event else { return }
            self.transition(to: .collapsed)
        }
        eventWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: work)
    }

    /// Убрать карточку события досрочно.
    func dismissEvent() {
        eventWork?.cancel()
        eventWork = nil
        if state == .event { transition(to: .collapsed) }
    }

    /// Раскрытие по наведению может быть отложенным: с задержкой остров
    /// не распахивается от случайного пролёта курсора.
    private func scheduleHoverOpen() {
        guard hoverWork == nil else { return }
        let target = hoverTarget

        guard settings.hoverDelay > 0 else {
            transition(to: target)
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Обнулять нужно всегда, а не только после удачного перехода:
            // иначе одна неудачная попытка навсегда блокирует следующие —
            // `scheduleHoverOpen` выходит по непустому `hoverWork`.
            defer { self.hoverWork = nil }
            guard self.state == .collapsed else { return }
            self.transition(to: target)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.hoverDelay, execute: work)
    }

    private func scheduleAutoCollapse() {
        autoCollapseWork?.cancel()
        autoCollapseWork = nil
        guard settings.autoCollapseAfter > 0, state == .expanded else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .expanded else { return }
            self.collapse()
        }
        autoCollapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.autoCollapseAfter, execute: work)
    }

    /// Куда ведёт наведение: в раскрытую панель, если ей есть что показать,
    /// иначе — просто подросший остров.
    private var hoverTarget: NotchState {
        settings.expandOnHover && hasContent ? .expanded : .peek
    }

    func toggleExpanded() {
        if state == .expanded {
            transition(to: .collapsed)
        } else {
            transition(to: hasContent ? .expanded : .peek)
        }
    }

    func collapse() {
        transition(to: .collapsed)
    }

    func expand() {
        transition(to: .expanded)
    }

    private func transition(to next: NotchState) {
        guard state != next else { return }

        // Сворачивание тянется дольше раскрытия — так остров успокаивается,
        // а не исчезает рывком.
        let isShrinking = next.rank < state.rank
        withAnimation(animation(shrinking: isShrinking)) {
            state = next
        }

        if next == .collapsed {
            hoverWork?.cancel()
            hoverWork = nil
            eventWork?.cancel()
            eventWork = nil
        }
        scheduleAutoCollapse()
    }
}

