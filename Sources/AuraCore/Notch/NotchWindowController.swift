import AppKit
import Combine
import SwiftUI

/// Держит панель на нужном экране и связывает её с моделью состояния.
@MainActor
final class NotchWindowController {
    private var panel: NotchPanel?
    private let viewModel: NotchViewModel
    private let activities: ActivityCenter
    private let media: NowPlayingProvider
    private let settings: SettingsStore
    private let spectrum: AudioSpectrumMonitor
    private let lyrics: LyricsProvider
    private let shelf: ShelfService
    private let mouse = MouseTracker()
    private let fullScreen = FullScreenWatcher()
    private var cancellables = Set<AnyCancellable>()
    private var isHiddenByFullScreen = false

    init(
        activities: ActivityCenter,
        media: NowPlayingProvider,
        settings: SettingsStore,
        spectrum: AudioSpectrumMonitor,
        lyrics: LyricsProvider,
        shelf: ShelfService
    ) {
        self.activities = activities
        self.media = media
        self.settings = settings
        self.spectrum = spectrum
        self.lyrics = lyrics
        self.shelf = shelf
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
            self?.shelf.add(urls: urls)
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
        )
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        panel.contentView = container
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
                self?.resizeWindow(expanded: isExpanded)
            }
            .store(in: &cancellables)

        activities.$activities
            .map { [weak viewModel] in
                $0.isEmpty ? 0 : (viewModel?.accessorySlotWidth ?? 44) * 2
            }
            .removeDuplicates()
            .sink { [weak viewModel] width in
                withAnimation(AuraAnimation.notch) {
                    viewModel?.compactAccessoryWidth = width
                }
            }
            .store(in: &cancellables)

        mouse.onMove = { [weak self] point, speed in
            guard let self else { return }
            self.fullScreen.check()
            self.followMouseIfNeeded(point)

            guard !self.isHiddenByFullScreen, !self.isHiddenByUser else {
                self.panel?.ignoresMouseEvents = true
                return
            }

            // Небольшой запас, чтобы клик у самого края формы не проваливался.
            let isDragging = NSEvent.pressedMouseButtons & 1 != 0
            let padding: CGFloat = isDragging ? -70 : -3
            let interactive = self.viewModel.interactiveRectOnScreen.insetBy(dx: padding, dy: padding)
            self.panel?.ignoresMouseEvents = !interactive.contains(point)

            self.viewModel.handleMouseMoved(to: point, speed: speed)
        }
        mouse.start()

        fullScreen.onChange = { [weak self] isFullScreen in
            guard let self else { return }
            self.isHiddenByFullScreen = self.settings.hideInFullScreen && isFullScreen
            self.updatePanelVisibility()
        }
        fullScreen.start { ScreenGeometry.preferredScreen() }

        NSLog(
            "Aura: вырез %@ %.0fx%.0f на экране %.0fx%.0f",
            geometry.isPhysical ? "физический" : "виртуальный",
            geometry.notchSize.width, geometry.notchSize.height,
            geometry.screenFrame.width, geometry.screenFrame.height
        )
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
            apply(size: NotchViewModel.windowSize, to: panel)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                guard let self, self.viewModel.state != .expanded, let panel = self.panel
                else { return }
                self.apply(size: self.compactWindowSize, to: panel)
            }
        }
    }

    private var compactWindowSize: CGSize {
        let geometry = viewModel.geometry
        return CGSize(
            width: geometry.notchSize.width + viewModel.accessorySlotWidth * 2 + 120,
            height: geometry.notchSize.height + 60
        )
    }

    private func apply(size: CGSize, to panel: NSPanel) {
        let geometry = viewModel.geometry
        viewModel.currentWindowSize = size
        panel.setFrame(
            CGRect(
                x: geometry.notchRect.midX - size.width / 2,
                y: geometry.screenFrame.maxY - size.height,
                width: size.width,
                height: size.height
            ),
            display: false
        )
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

    func toggle() {
        viewModel.toggleExpanded()
    }

    /// Ручное скрытие из меню. Отдельно от полноэкранного режима: пользователь
    /// мог выключить вырез сам, и возврат из видео не должен его включать.
    private var isHiddenByUser = false

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
