import AppKit
import Combine
import SwiftUI

/// Держит панель на нужном экране и связывает её с моделью состояния.
@MainActor
final class NotchWindowController {
    private var panel: NotchPanel?
    private var container: NotchContainerView?
    private var hosting: NSView?
    private let viewModel: NotchViewModel
    private let activities: ActivityCenter
    private let media: NowPlayingProvider
    private let settings: SettingsStore
    private let spectrum: AudioSpectrumMonitor
    private let lyrics: LyricsProvider
    private let shelf: ShelfService
    private let notifications: NotificationMirrorProvider
    private let mouse = MouseTracker()
    private let modifiers = ModifierWatcher()
    private lazy var dropActions = DropActions { [weak self] urls in
        self?.shelf.add(urls: urls)
    }
    private let fullScreen = FullScreenWatcher()
    private var cancellables = Set<AnyCancellable>()
    private var isHiddenByFullScreen = false

    init(
        activities: ActivityCenter,
        media: NowPlayingProvider,
        settings: SettingsStore,
        spectrum: AudioSpectrumMonitor,
        lyrics: LyricsProvider,
        shelf: ShelfService,
        notifications: NotificationMirrorProvider
    ) {
        self.activities = activities
        self.media = media
        self.settings = settings
        self.spectrum = spectrum
        self.lyrics = lyrics
        self.shelf = shelf
        self.notifications = notifications
        // Экранов может не быть вовсе — например, при закрытой крышке без
        // внешнего монитора. Тогда работаем с запасной геометрией и ждём,
        // пока экран появится.
        let geometry = ScreenGeometry.preferredScreen()
            .map { ScreenGeometry.geometry(for: $0, settings: settings) }
            ?? ScreenGeometry.fallbackGeometry()
        self.viewModel = NotchViewModel(geometry: geometry, settings: settings)
    }

    func attachToScreenWithNotch() {
        guard let screen = ScreenGeometry.preferredScreen() else { return }
        let geometry = ScreenGeometry.geometry(for: screen, settings: settings)
        viewModel.geometry = geometry
        viewModel.collapse()

        let size = NotchViewModel.windowSize
        let frame = CGRect(
            x: geometry.notchRect.midX - size.width / 2,
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        if let panel {
            panel.setFrame(frame, display: true)
            return
        }

        let panel = NotchPanel(contentRect: frame)
        // По умолчанию окно не участвует в обработке мыши совсем: оно шире
        // выреза и иначе накрывало бы строку меню целиком — вместе с иконками
        // других приложений и нашей собственной.
        panel.ignoresMouseEvents = true

        let container = NotchContainerView(frame: CGRect(origin: .zero, size: size))
        container.interactiveRect = { [weak viewModel] in
            viewModel?.interactiveRectInWindow ?? .zero
        }

        // Файл, который тащат к вырезу, раскрывает панель — чтобы было видно,
        // куда именно его бросать.
        container.onDragEnter = { [weak self] in
            self?.viewModel.expand()
        }
        container.onDrop = { [weak self] urls in
            guard let self else { return }
            guard self.settings.dropShowsMenu else {
                self.shelf.add(urls: urls)
                return
            }
            self.dropActions.present(for: urls, at: NSEvent.mouseLocation)
        }

        // Пока курсор внутри формы, окно забирает мышь себе и глобальный
        // монитор молчит. Дальше движение приходит отсюда.
        container.onMouseMoved = { [weak self] in
            self?.handleMouse(at: NSEvent.mouseLocation, speed: 0)
        }

        container.onScrollHorizontal = { [weak self] delta in
            self?.switchTrack(by: delta)
        }

        let hosting = NSHostingView(
            rootView: NotchRootView()
                .environmentObject(viewModel)
                .environmentObject(activities)
                .environmentObject(media)
                .environmentObject(settings)
                .environmentObject(spectrum)
                .environmentObject(lyrics)
                .environmentObject(shelf)
                .environmentObject(notifications)
                .environmentObject(modifiers)
        )
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        panel.contentView = container
        self.container = container
        self.hosting = hosting
        panel.orderFrontRegardless()
        self.panel = panel
        apply(size: compactWindowSize, to: panel)

        // Появилась активность — вырез раздвигается, освобождая место под
        // компактные слоты; исчезла — снова сливается с физическим вырезом.
        viewModel.$state
            .map { $0 == .expanded }
            .removeDuplicates()
            .sink { [weak self] isExpanded in
                self?.media.isDetailed = isExpanded
            }
            .store(in: &cancellables)

        // Окно растёт не только под раскрытую панель: карточка уведомления
        // тоже не помещается в размер выреза.
        //
        // И растёт заранее — как только курсор подошёл. Смена размера окна
        // это синхронная перекладка всего дерева видов; в кадре, где
        // начинается анимация раскрытия, она стоит заметного рывка.
        Publishers.CombineLatest(
            viewModel.$state.map { $0.rank >= NotchState.event.rank },
            viewModel.$proximity.map { $0 > 0.1 }
        )
        .map { $0 || $1 }
        .removeDuplicates()
        .sink { [weak self] needsRoom in
            self?.resizeWindow(expanded: needsRoom)
        }
        .store(in: &cancellables)




        mouse.onMove = { [weak self] point, speed in
            self?.handleMouse(at: point, speed: speed)
        }
        mouse.start()
        modifiers.start()

        // Состав содержимого: от него зависит и высота панели, и то,
        // раскрывать ли её вообще. Пустая панель — чёрный прямоугольник
        // и ничего больше, поэтому наведение тогда только растит остров.
        Publishers.CombineLatest3(
            media.$nowPlaying,
            activities.$activities,
            shelf.$items
        )
        .sink { [weak viewModel, weak self] playing, activities, shelf in
            guard let viewModel, let self else { return }
            let others = activities.filter { $0.id != "media.nowplaying" }.count

            // Всё одним движением и одной кривой.
            //
            // Раньше ширина слотов ехала своей анимацией, состав содержимого —
            // своей, а список активностей — третьей. Когда трек меняется,
            // все три случаются в одном кадре, и пружины накладываются друг
            // на друга: остров дёргается и не успокаивается.
            withAnimation(AuraAnimation.accessory(settings: self.settings)) {
                viewModel.compactAccessoryWidth = activities.isEmpty
                    ? 0
                    : viewModel.accessorySlotWidth * 2
                viewModel.hasMedia = playing != nil
                viewModel.hasShelf = !shelf.isEmpty
                viewModel.extraRowCount = others
                viewModel.hasContent = playing != nil || !activities.isEmpty || !shelf.isEmpty
            }
        }
        .store(in: &cancellables)

        // Окно обязано следовать за высотой панели.
        //
        // Панель измеряет свою настоящую высоту уже после того, как окно
        // получило размер по предварительной оценке. Если окно за ней не
        // идёт, низ панели просто срезается его краем — и остров выглядит
        // обрубленным ровно тогда, когда содержимого больше обычного.
        Publishers.CombineLatest3(
            viewModel.$extraRowCount.removeDuplicates(),
            notifications.$unread.map { !$0.isEmpty }.removeDuplicates(),
            media.$accessDenied.removeDuplicates()
        )
        .sink { [weak self] _, hasHeader, accessDenied in
            guard let self else { return }
            withAnimation(AuraAnimation.accessory(settings: self.settings)) {
                self.viewModel.hasNotificationHeader = hasHeader
                self.viewModel.hasAccessBanner = accessDenied
            }
            guard self.viewModel.state.rank >= NotchState.event.rank else { return }
            DispatchQueue.main.async { self.resizeWindow(expanded: true) }
        }
        .store(in: &cancellables)

        // Уведомление прочитали — карточке больше нечего показывать,
        // и остров обязан свернуться, а не остаться пустой коробкой.
        notifications.$latest
            .map { $0 == nil }
            .removeDuplicates()
            .sink { [weak viewModel] isEmpty in
                if isEmpty { viewModel?.dismissEvent() }
            }
            .store(in: &cancellables)

        fullScreen.onChange = { [weak self] isFullScreen in
            guard let self else { return }
            self.isHiddenByFullScreen = self.settings.hideInFullScreen && isFullScreen
            self.updatePanelVisibility()

            // Пока идёт полноэкранное видео, опрашивать плеер незачем:
            // панель всё равно спрятана, а опрос — это круг AppleScript
            // и перебор аудио-объектов системы. Заодно глохнет спектр:
            // он включается только под играющую карточку.
            guard self.settings.enableMusic else { return }
            self.isHiddenByFullScreen ? self.media.stop() : self.media.start()
        }
        fullScreen.start { ScreenGeometry.preferredScreen() }

        NSLog(
            "Aura: вырез %@ %.0fx%.0f на экране %.0fx%.0f",
            geometry.isPhysical ? "физический" : "виртуальный",
            geometry.notchSize.width, geometry.notchSize.height,
            geometry.screenFrame.width, geometry.screenFrame.height
        )
    }

    /// Движение курсора — из глобального монитора или из зоны над самой
    /// панелью, обработка одна.
    ///
    /// Порядок здесь важен: сначала состояние, потом решение о перехвате мыши.
    /// Наоборот было раньше — и перехват считался по форме, которая ещё не
    /// знала про это движение.
    private func handleMouse(at point: CGPoint, speed: CGFloat) {
        fullScreen.check()
        followMouseIfNeeded(point)

        guard !isHiddenByFullScreen, !isHiddenByUser else {
            panel?.ignoresMouseEvents = true
            return
        }

        viewModel.handleMouseMoved(to: point, speed: speed)

        // Небольшой запас, чтобы клик у самого края формы не проваливался.
        let isDragging = NSEvent.pressedMouseButtons & 1 != 0
        let padding: CGFloat = isDragging ? -70 : -3
        let interactive = viewModel.interactiveRectOnScreen.insetBy(dx: padding, dy: padding)
        panel?.ignoresMouseEvents = !interactive.contains(point)
    }

    /// Снимок состояния для команды `aura status` — иначе про панель, которая
    /// не показывается, нечего сказать кроме «не работает».
    var diagnostics: [String: Any] {
        [
            "окноСоздано": panel != nil,
            "окноВидимо": panel?.isVisible ?? false,
            "состояние": String(describing: viewModel.state),
            "полноэкранныйРежим": isHiddenByFullScreen,
            "вырезШирина": Int(viewModel.geometry.notchSize.width),
            "вырезВысота": Int(viewModel.geometry.notchSize.height),
            "вырезФизический": viewModel.geometry.isPhysical,
            "слотыШирина": Int(viewModel.compactAccessoryWidth),
            // Панель обязана помещаться в окно: иначе низ срезается краем.
            "панельВысота": Int(viewModel.contentSize.height),
            "окноВысота": Int(viewModel.currentWindowSize.height),
            
        ]
    }

    /// Размер окна меняется вместе с состоянием.
    ///
    /// Прозрачное окно в полтысячи точек высотой система пересобирает целиком
    /// на каждой перерисовке полосок — а видно при этом один вырез. В покое
    /// окно сжимается до него, и это снимает основную долю нагрузки.
    ///
    /// Момент важен: растём до начала анимации, сжимаемся заметно после её
    /// конца — иначе панель дёргается прямо во время движения.
    private func resizeWindow(expanded: Bool) {
        guard let panel else { return }

        if expanded {
            apply(size: viewModel.expandedWindowSize, to: panel)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                guard let self, self.viewModel.state.rank < NotchState.event.rank,
                      self.viewModel.proximity <= 0.1,
                      let panel = self.panel else { return }
                self.apply(size: self.compactWindowSize, to: panel)
            }
        }
    }

    private var compactWindowSize: CGSize {
        CGSize(
            width: viewModel.compactWindowWidth,
            height: viewModel.geometry.notchSize.height + 60
        )
    }

    private func apply(size: CGSize, to panel: NSPanel) {
        // Лишняя перекладка дерева видов ничего не меняет, но стоит кадра.
        guard size != viewModel.currentWindowSize else { return }

        let geometry = viewModel.geometry
        viewModel.currentWindowSize = size
        let frame = CGRect(
            x: geometry.notchRect.midX - size.width / 2,
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        // Окно, его содержимое и перерисовка — одним кадром.
        //
        // Core Animation с удовольствием анимирует переезд окна, если размер
        // меняется посреди `withAnimation`: оно едет из старых координат
        // в новые, а содержимое приколото к окну — со стороны это выезд
        // острова вбок. Отсюда `setDisableActions`.
        //
        // А `NSHostingView` откладывает свою раскладку до следующего прохода
        // рун-лупа. Окно уже переехало, остров ещё центрируется по старой
        // ширине — и один кадр он нарисован не на месте. Именно этот лишний
        // кадр и виден на раскрытии, поэтому раскладку добиваем руками
        // и заставляем окно нарисоваться, не дожидаясь следующего прохода.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        panel.setFrame(frame, display: false)
        let bounds = CGRect(origin: .zero, size: size)
        container?.frame = bounds
        hosting?.frame = bounds
        hosting?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()

        CATransaction.commit()
    }

    /// Переносит панель на экран под курсором.
    ///
    /// На встроенном экране вырез физический, на внешнем рисуется виртуальный —
    /// поэтому переезд имеет смысл только когда пользователь сам его включил.
    private func followMouseIfNeeded(_ point: CGPoint) {
        guard settings.followMouseScreen, viewModel.state == .collapsed else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              screen.frame != viewModel.geometry.screenFrame else { return }

        let geometry = ScreenGeometry.geometry(for: screen, settings: settings)
        viewModel.geometry = geometry
        if let panel { apply(size: compactWindowSize, to: panel) }
    }

    /// Горизонтальный жест переключает трек, но только когда накопится
    /// уверенное движение — иначе трек прыгал бы от любого касания трекпада.
    private func switchTrack(by delta: CGFloat) {
        guard settings.scrollSwitchesTrack else { return }
        horizontalScroll += delta

        guard abs(horizontalScroll) > 60,
              Date().timeIntervalSince(lastTrackSwitch) > 0.6 else { return }

        media.send(horizontalScroll > 0 ? .previous : .next)
        horizontalScroll = 0
        lastTrackSwitch = Date()
    }

    func toggle() {
        viewModel.toggleExpanded()
    }

    /// Показать карточку уведомления.
    func presentEvent(hold: TimeInterval) {
        guard !isHiddenByUser, !isHiddenByFullScreen else { return }
        viewModel.presentEvent(hold: hold)
    }

    /// Ручное скрытие из меню. Отдельно от полноэкранного режима: пользователь
    /// мог выключить вырез сам, и возврат из видео не должен его включать.
    private var isHiddenByUser = false
    private var horizontalScroll: CGFloat = 0
    private var lastTrackSwitch = Date.distantPast

    func setVisible(_ visible: Bool) {
        isHiddenByUser = !visible
        updatePanelVisibility()
    }

    private func updatePanelVisibility() {
        guard let panel else { return }
        if isHiddenByUser || isHiddenByFullScreen {
            viewModel.collapse()
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func open() {
        viewModel.expand()
    }

    func close() {
        viewModel.collapse()
    }

}
