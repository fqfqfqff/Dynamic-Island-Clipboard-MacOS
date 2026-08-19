import SwiftUI
import AppKit
import Combine

/// Состояние выреза. Переходы: collapsed ⇄ peek → expanded.
enum NotchState: Equatable {
    /// Незаметная чёрная пилюля ровно по форме выреза.
    case collapsed
    /// Курсор рядом — вырез слегка подрос и намекает, что на него можно нажать.
    case peek
    /// Раскрытая панель с содержимым.
    case expanded

    /// Насколько состояние «больше» предыдущего — по этому выбирается
    /// анимация: раскрытие или сворачивание.
    var rank: Int {
        switch self {
        case .collapsed: 0
        case .peek: 1
        case .expanded: 2
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
    static let windowSize = CGSize(width: 720, height: 560)

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
    static let contentTopInset: CGFloat = 18

    var expandedSize: CGSize {
        // Панель ниже своего содержимого выдавливает его вверх, и обложка
        // заезжает под вырез камеры. Поэтому высота снизу ограничена.
        let minimum = geometry.menuBarHeight + Self.contentTopInset + playerContentHeight
        return CGSize(
            width: settings.expandedWidth,
            height: max(settings.expandedHeight, minimum)
        )
    }

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
            let lift = settings.reactToProximity ? proximity * 4 : 0
            return CGSize(
                width: notch.width + compactAccessoryWidth + lift * 2,
                height: notch.height + lift
            )
        case .peek:
            return CGSize(
                width: notch.width + compactAccessoryWidth + 28,
                height: notch.height + 10
            )
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

    /// Зона притяжения курсора в глобальных координатах: чуть шире выреза,
    /// чтобы не приходилось целиться пиксель в пиксель.
    var hoverRectOnScreen: CGRect {
        geometry.notchRect.insetBy(dx: -18, dy: -6)
    }

    /// Зона, при выходе из которой подсказка гаснет. Она заметно шире зоны
    /// входа: без этого запаса вырез мигал, когда курсор шёл вдоль кромки.
    var hoverExitRectOnScreen: CGRect {
        geometry.notchRect.insetBy(dx: -40, dy: -22)
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
            if abs(next - proximity) > 0.02 {
                withAnimation(.smooth(duration: 0.25)) { proximity = next }
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
        guard settings.reactToProximity else {
            let plain = shrinking ? AuraAnimation.notchCollapse : AuraAnimation.notch
            guard settings.animationSpeed != 1 else { return plain }
            return .spring(
                response: (shrinking ? 0.6 : 0.48) * settings.animationSpeed,
                dampingFraction: shrinking ? 0.9 : 0.82
            )
        }

        // Скорость курсора подтягивает длительность, но не схлопывает её:
        // даже самое резкое движение оставляет анимацию видимой.
        let normalized = min(1, lastSpeed / 2200)
        let base = shrinking ? 0.66 : 0.52
        let fastest = shrinking ? 0.46 : 0.36
        let response = (base - (base - fastest) * Double(normalized)) * settings.animationSpeed

        return .spring(response: response, dampingFraction: shrinking ? 0.94 : 0.86)
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

    /// Раскрытие по наведению может быть отложенным: с задержкой остров
    /// не распахивается от случайного пролёта курсора.
    private func scheduleHoverOpen() {
        guard hoverWork == nil else { return }
        let target: NotchState = settings.expandOnHover ? .expanded : .peek

        guard settings.hoverDelay > 0 else {
            transition(to: target)
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .collapsed else { return }
            self.transition(to: target)
            self.hoverWork = nil
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

    func toggleExpanded() {
        transition(to: state == .expanded ? .collapsed : .expanded)
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
        }
        scheduleAutoCollapse()
    }
}

