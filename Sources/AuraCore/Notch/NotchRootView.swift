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
        AuraTheme.accent(for: media.nowPlaying?.accent ?? .pink, settings: settings)
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

    /// Все слои существуют всегда и лишь меняют прозрачность.
    ///
    /// Раньше они создавались и уничтожались по `if isExpanded`. Каждое такое
    /// появление — это новый слой, новая маска и новое размытие, собранные
    /// прямо посреди анимации: отсюда и рывок, и ощущение дешёвого перехода.
    /// Теперь дерево видов при раскрытии не меняется вовсе.
    private var panelBackground: some View {
        ZStack {
            shape.fill(.black)

            decoration
                .opacity(isExpanded ? 1 : 0)
        }
        .overlay { border }
        .shadow(
            color: .black.opacity(settings.showShadow && isExpanded ? 0.5 : 0),
            radius: 20,
            y: 8
        )
    }

    /// Оформление раскрытой панели, собранное в один слой: одна маска,
    /// одно обрезание по форме, один композит.
    private var decoration: some View {
        ZStack {
            backdrop
            glass
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: .black.opacity(0.35), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .compositingGroup()
        .clipShape(shape)
        .mask(fadeMask)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var backdrop: some View {
        switch settings.backgroundStyle {
        case "gradient":
            AuraTheme.gradient(settings.gradientPreset)
                .opacity(settings.backdropStrength)
        case "solid":
            Color.clear
        default:
            if let artwork = media.nowPlaying?.blurredArtwork ?? media.nowPlaying?.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .saturation(1.4)
                    .opacity(settings.backdropStrength)
            }
        }
    }

    @ViewBuilder
    private var glass: some View {
        if settings.glassStyle != "off" {
            if #available(macOS 26.0, *) {
                switch settings.glassStyle {
                case "clear":
                    Color.clear.glassEffect(.clear, in: shape)
                case "tinted":
                    Color.clear.glassEffect(.regular.tint(accentColor.opacity(0.22)), in: shape)
                default:
                    Color.clear.glassEffect(.regular, in: shape)
                }
            } else {
                Rectangle().fill(.ultraThinMaterial).opacity(0.35)
            }
        }
    }

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

    /// Переход к чёрному под вырезом.
    ///
    /// Доля считается от постоянной высоты раскрытой панели, а не от текущей:
    /// иначе маска пересчитывалась на каждом кадре анимации и края шва
    /// подрагивали.
    private var fadeMask: LinearGradient {
        let reference = max(viewModel.expandedSize.height, 1)
        let notchShare = min(0.5, viewModel.geometry.notchSize.height / reference)

        return LinearGradient(
            stops: [
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

    /// Оба состояния существуют одновременно и переключаются прозрачностью.
    /// Никаких вставок и удалений — значит, нечему дёргаться.
    private var content: some View {
        ZStack(alignment: .top) {
            compactActivity
                .opacity(isExpanded ? 0 : 1)

            // Содержимое собирается заранее — как только курсор дошёл до
            // выреза, — и к моменту раскрытия уже готово. В покое его нет
            // вовсе: иначе плеер с его таймерами работал бы вхолостую.
            if viewModel.state != .collapsed {
                expandedContent
                    .padding(.top, viewModel.geometry.menuBarHeight + NotchViewModel.contentTopInset)
                    .opacity(isExpanded ? 1 : 0)
                    .scaleEffect(isExpanded ? 1 : 0.97, anchor: .top)
            }
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
            .transition(.opacity)
        } else if viewModel.state == .peek, settings.showChevronHint {
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 1)
                .transition(.opacity)
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
