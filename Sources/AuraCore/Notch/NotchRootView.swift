import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var activities: ActivityCenter
    @EnvironmentObject private var media: NowPlayingProvider
    @EnvironmentObject private var settings: SettingsStore

    @State private var isPressed = false

    private var size: CGSize { viewModel.contentSize }
    private var isExpanded: Bool { viewModel.state == .expanded }

    private var accentColor: Color {
        AuraTheme.accent(
            for: media.nowPlaying?.accent ?? .pink,
            settings: settings
        )
    }

    private var shape: NotchShape {
        NotchShape(
            topRadius: isExpanded ? 12 : 6,
            bottomRadius: isExpanded ? 26 : viewModel.geometry.notchSize.height / 2
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            panelBackground
            content
        }
        .frame(width: size.width, height: size.height)
        // Отклик на нажатие: остров слегка проседает под курсором, как
        // физическая кнопка. Без этого клик ощущается как промах.
        .scaleEffect(isPressed ? 0.985 : 1, anchor: .top)
        .animation(AuraAnimation.touch, value: isPressed)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard settings.doubleClickTogglesPlayback, media.nowPlaying != nil else {
                viewModel.toggleExpanded()
                return
            }
            media.send(.togglePlayPause)
        }
        .onTapGesture { viewModel.toggleExpanded() }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Фон

    /// Фон панели — та же обложка, растянутая на весь остров и размытая
    /// до состояния цветного стекла. Обложка в центре и подложка под ней —
    /// одно изображение в двух масштабах, поэтому цвета сходятся идеально.
    ///
    /// Верхняя полоса высотой с вырез остаётся чистым чёрным: там панель
    /// прилегает к камере и кромке экрана, и любой оттенок читался бы как шов.
    private var panelBackground: some View {
        shape
            .fill(.black)
            .overlay { artworkBackdrop }
            .overlay { glass }
            .overlay { readabilityShade }
            // Слои фона склеиваются в один растр: иначе система пересобирает
            // каждый из них отдельно на каждом кадре анимации.
            .compositingGroup()
            .overlay { border }
            .shadow(
                color: .black.opacity(settings.showShadow && isExpanded ? 0.55 : 0),
                radius: 22,
                y: 10
            )
    }

    /// Тонкая светлая кромка, как у острова на iPhone.
    ///
    /// Не ровная обводка по кругу, а градиент: вверху ярче, книзу гаснет —
    /// будто на край падает свет сверху. Ровная линия одинаковой яркости
    /// выглядит нарисованной, эта — объёмной.
    @ViewBuilder
    private var border: some View {
        if settings.showBorder {
            shape.stroke(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(isExpanded ? 0.38 : 0.22), location: 0),
                        .init(color: .white.opacity(isExpanded ? 0.14 : 0.08), location: 0.35),
                        .init(color: .white.opacity(0.04), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.8
            )
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var artworkBackdrop: some View {
        if isExpanded, settings.backgroundStyle == "gradient" {
            AuraTheme.gradient(settings.gradientPreset)
                .opacity(settings.backdropStrength)
                .clipShape(shape)
                .mask(fadeMask)
                .allowsHitTesting(false)
                .transition(.opacity.animation(AuraAnimation.contentIn))
        } else if isExpanded, settings.backgroundStyle == "artwork",
                  let artwork = media.nowPlaying?.blurredArtwork ?? media.nowPlaying?.artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                // Дополнительное размытие — только если пользователь просит
                // больше, чем даёт заранее подготовленная копия.
                .blur(radius: max(0, settings.backdropBlur - 26) * 0.4, opaque: true)
                .saturation(1.4)
                .opacity(settings.backdropStrength)
                .clipShape(shape)
                .mask(fadeMask)
                .allowsHitTesting(false)
                .transition(.opacity.animation(AuraAnimation.contentIn))
        }
    }

    /// Стекло поверх размытой обложки: добавляет матовость и глубину,
    /// из-за которых фон читается как стекло, а не как размытая картинка.
    @ViewBuilder
    private var glass: some View {
        if isExpanded, settings.glassStyle != "off" {
            Group {
                if #available(macOS 26.0, *) {
                    switch settings.glassStyle {
                    case "clear":
                        Color.clear.glassEffect(.clear, in: shape)
                    case "tinted":
                        Color.clear.glassEffect(
                            .regular.tint(accentColor.opacity(0.22)),
                            in: shape
                        )
                    default:
                        Color.clear.glassEffect(.regular, in: shape)
                    }
                } else {
                    shape.fill(.ultraThinMaterial).opacity(0.35)
                }
            }
            .mask(fadeMask)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Лёгкое затемнение к низу — чтобы белый текст поверх светлой обложки
    /// оставался читаемым.
    @ViewBuilder
    private var readabilityShade: some View {
        if isExpanded {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: .black.opacity(0.35), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(shape)
            .allowsHitTesting(false)
        }
    }

    /// Маска перехода: под вырезом — чистый чёрный, ниже оформление
    /// проявляется. Точка перехода привязана к высоте выреза, а не к доле
    /// панели, иначе при изменении её размера шов вылезал бы наружу.
    private var fadeMask: LinearGradient {
        let notchShare = min(0.5, viewModel.geometry.notchSize.height / max(size.height, 1))
        return LinearGradient(
            stops: [
                // До нижней кромки выреза — чистый чёрный, без единого оттенка.
                .init(color: .clear, location: 0),
                .init(color: .clear, location: notchShare * 0.85),
                .init(color: .black.opacity(0.4), location: notchShare * 1.35),
                .init(color: .black.opacity(0.85), location: notchShare * 2),
                .init(color: .black, location: min(1, notchShare * 2.8)),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Содержимое

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .collapsed:
            compactActivity
        case .peek where !settings.showChevronHint:
            EmptyView()
        case .peek:
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 1)
                .transition(.opacity.animation(AuraAnimation.contentIn))
        case .expanded:
            expandedContent
                .padding(.top, viewModel.geometry.menuBarHeight + NotchViewModel.contentTopInset)
                .transition(.auraContent)
        }
    }

    @ViewBuilder
    private var compactActivity: some View {
        if let featured = activities.featured {
            CompactActivityView(
                activity: featured,
                extraCount: activities.hiddenCount,
                notchWidth: viewModel.geometry.notchSize.width,
                slotWidth: viewModel.accessorySlotWidth
            )
            .frame(height: viewModel.geometry.notchSize.height)
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActivitiesPane()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

struct PlaceholderPane: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
