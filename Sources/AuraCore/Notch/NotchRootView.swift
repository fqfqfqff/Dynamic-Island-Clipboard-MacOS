import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var activities: ActivityCenter
    @EnvironmentObject private var media: NowPlayingProvider
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var notifications: NotificationMirrorProvider

    @State private var isPressed = false
    @State private var artworkPulse = false

    private var size: CGSize { viewModel.contentSize }

    /// Обложку рисует один общий слой, а не каждое состояние по-своему.
    ///
    /// Это и есть разница между островом и панелью, которая просто возникла:
    /// картинка не появляется заново в новом месте, а переезжает и меняет
    /// размер. Раньше компактный значок и большая обложка были двумя разными
    /// видами, и переход между ними был перекрёстным затуханием.
    private var isHeroActive: Bool {
        guard media.nowPlaying != nil else { return false }
        return isExpanded || activities.featured?.id == "media.nowplaying"
    }

    /// Пора ли собирать содержимое раскрытой панели.
    private var isContentPrepared: Bool {
        // Порог выше, чем у роста окна: сначала окно меняет размер с лёгким
        // деревом видов, и только потом дерево тяжелеет.
        viewModel.state != .collapsed || viewModel.proximity > 0.2
    }

    private var heroSide: CGFloat { isExpanded ? settings.artworkSize : 22 }

    private var heroRadius: CGFloat {
        isExpanded ? settings.artworkCornerRadius : 5
    }

    /// Куда обложка едет. В раскрытой панели — на своё место в карточке,
    /// в компактном виде — в левый слот у самой кромки выреза.
    private var heroCenter: CGPoint {
        if isExpanded {
            return CGPoint(
                x: size.width / 2,
                y: viewModel.geometry.menuBarHeight
                    + NotchViewModel.contentTopInset
                    + settings.artworkSize / 2
            )
        }
        return CGPoint(
            x: size.width / 2
                - viewModel.geometry.notchSize.width / 2
                - viewModel.accessorySlotWidth / 2,
            y: viewModel.geometry.notchSize.height / 2
        )
    }

    @ViewBuilder
    private var heroArtwork: some View {
        Group {
            if let image = media.nowPlaying?.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "waveform")
                            .font(.system(size: heroSide * 0.26, weight: .light))
                            .foregroundStyle(.white.opacity(0.4))
                    }
            }
        }
        .frame(width: heroSide, height: heroSide)
        .clipShape(RoundedRectangle(cornerRadius: heroRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: heroRadius, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: accentColor.opacity(isExpanded ? 0.35 : 0), radius: 18, y: 8)
        .scaleEffect(artworkPulse ? 1.05 : 1)
        .animation(AuraAnimation.touch, value: artworkPulse)
        .position(heroCenter)
        .allowsHitTesting(false)
    }
    private var isExpanded: Bool { viewModel.state == .expanded }
    private var isEvent: Bool { viewModel.state == .event }

    private var accentColor: Color {
        AuraTheme.accent(for: media.nowPlaying?.accent ?? .pink, settings: settings)
    }

    private var shape: NotchShape {
        switch viewModel.state {
        case .expanded:
            NotchShape(topRadius: 12, bottomRadius: 26)
        case .event:
            NotchShape(topRadius: 10, bottomRadius: 22)
        default:
            NotchShape(topRadius: 6, bottomRadius: viewModel.geometry.notchSize.height / 2)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            panelBackground
            // Содержимое обязано быть заперто в размер острова.
            //
            // Иначе оно раздувает контейнер: в состоянии `peek` панель уже
            // собрана (прозрачная, но собранная), карточка плеера высотой
            // под двести точек растягивает ZStack, и чёрная форма заливает
            // всё это целиком. На экране это выглядело так, будто от
            // наведения под вырезом разворачивается чёрный прямоугольник.
            content
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipped()
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
        .onTapGesture {
            // Клик по карточке — это «увидел»: значок с числом непрочитанных
            // после него уходит, а сама карточка сворачивается.
            if isEvent, let message = notifications.latest {
                notifications.markRead(app: message.app)
                viewModel.dismissEvent()
            } else {
                viewModel.toggleExpanded()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        // Долгое нажатие — быстрое меню: пауза, спрятать остров, настройки.
        // То, за чем чаще всего лезут в строку состояния.
        .onLongPressGesture(minimumDuration: 0.45) {
            isPressed = false
            AppActions.showQuickMenu()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: media.nowPlaying?.title) { _, _ in
            artworkPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { artworkPulse = false }
        }
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

            // Рамка и обрезание обязательны: размытая обложка внутри
            // растягивается «по заполнению» и вылезает за форму панели —
            // отсюда цветной ореол по краям, а в свёрнутом виде слой
            // переживал даже нулевую прозрачность.
            decoration
                .frame(width: size.width, height: size.height)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
        }
        .overlay { border }
        .overlay {
            if isEvent, let message = notifications.latest {
                // Верхняя часть карточки — это физический вырез, там всё
                // и так чёрное. Обводка по его кромке обрывается и выглядит
                // сломанной, поэтому вверху она сходит на нет.
                EventRim(shape: shape, tint: message.tint)
                    .mask(rimMask)
            }
        }
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
            // Затемнение поверх обложки. Без него карточка выцветает в один
            // светлый тон: подписи под названием и цифры длительности на нём
            // не читаются вовсе. Обложка здесь — подкраска, а не фотография.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.25), location: 0),
                    .init(color: .black.opacity(0.42), location: 0.45),
                    .init(color: .black.opacity(0.62), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            glass
            topHighlight
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
                // `.fill` возвращает размер БОЛЬШЕ предложенного — картинка
                // выпирает, и обрезание по форме считается уже от её раздутых
                // границ. Отсюда цветная кромка вокруг панели. Рамку ставим
                // на саму картинку, до всех остальных слоёв.
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    // Насыщенность была 1.4 — обложка превращалась в цветное
                    // пятно во всю карточку и съедала текст.
                    .saturation(1.1)
                    .opacity(settings.backdropStrength * 0.62)
            }
        }
    }

    /// Тонкая световая кромка вдоль верха карточки — то, что на стекле
    /// читается как блик. Дешевле любого фильтра: один градиент.
    private var topHighlight: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.10), location: 0),
                .init(color: .clear, location: 0.22),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private var glass: some View {
        // Стекло поверх обложки даёт по кромке цветную кайму: Liquid Glass
        // преломляет то, что под ним, а под ним — насыщенная картинка.
        // На чёрном и на градиенте этого не происходит.
        if settings.glassStyle != "off", settings.backgroundStyle != "artwork" {
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

    /// Обводка проявляется только ниже выреза.
    private var rimMask: LinearGradient {
        let share = min(0.7, viewModel.geometry.menuBarHeight / max(viewModel.eventSize.height, 1))
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: share * 0.85),
                .init(color: .black, location: min(1, share * 1.5)),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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
                .opacity(isExpanded || isEvent ? 0 : 1)

            if isHeroActive {
                heroArtwork
            }

            // Карточка уведомления живёт только в своём состоянии: держать её
            // собранной всё время незачем — иконка приложения тянет за собой
            // картинку, а событий за день немного.
            if isEvent, let message = notifications.latest {
                EventCard(
                    message: message,
                    unread: notifications.unread[message.app] ?? 1,
                    onReply: notifications.canReply ? { notifications.reply() } : nil
                )
                    .frame(height: viewModel.eventSize.height - viewModel.geometry.menuBarHeight - 12)
                    .padding(.top, viewModel.geometry.menuBarHeight + 6)
                    .transition(.auraCompact)
            }

            // Содержимое собирается заранее — как только курсор подошёл
            // к вырезу, — и к моменту раскрытия уже готово. В покое его нет
            // вовсе: иначе плеер с его таймерами работал бы вхолостую.
            //
            // Условие именно по близости курсора, а не по состоянию: при
            // «раскрывать при наведении» остров идёт из свёрнутого прямо
            // в раскрытый, и всё дерево карточки собиралось бы в том же
            // кадре, где начинается анимация.
            if isContentPrepared {
                expandedContent
                    .environment(\.heroArtworkActive, isHeroActive)
                    .padding(.top, viewModel.geometry.menuBarHeight + NotchViewModel.contentTopInset)
                    .opacity(isExpanded ? 1 : 0)
                    // Только по вертикали: содержимое выезжает из-под кромки
                    // вниз и уходит обратно вверх. Масштаб «от центра» читался
                    // как движение вбок и выглядел неряшливо.
                    .offset(y: isExpanded ? 0 : -10)
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
                slotWidth: viewModel.accessorySlotWidth,
                showsArtwork: !isHeroActive,
                isLive: !isExpanded && !isEvent
            )
            .frame(height: viewModel.geometry.notchSize.height)
            .transition(.auraCompact)
        } else if settings.hintStyle != "none" {
            hint
        }
    }

    /// Подсказка при наведении.
    ///
    /// Верхние точки острова закрыты физическим вырезом — всё, что там
    /// нарисовано, пользователь просто не видит. Подсказка обязана жить
    /// в полосе под ним, а не «внизу рамки»: рамка начинается выше выреза.
    ///
    /// Вид существует всегда и лишь меняет прозрачность со смещением.
    /// Вставка и удаление вида — это отдельная анимация поверх нашей, и на
    /// стыке двух кривых движение перестаёт быть чисто вертикальным.
    private var hint: some View {
        let isPeeking = viewModel.state == .peek
        let strip = max(0, viewModel.contentSize.height - viewModel.geometry.menuBarHeight)

        return hintShape
            .frame(height: strip, alignment: .center)
            .padding(.top, viewModel.geometry.menuBarHeight)
            .opacity(isPeeking ? 1 : 0)
            .offset(y: isPeeking ? 0 : -12)
            // Своей анимации здесь нет намеренно: изменение состояния уже
            // обёрнуто в `withAnimation`, и подсказка едет ровно по той же
            // кривой, что и сама форма. Отдельный модификатор дал бы вторую
            // пружину поверх первой — на их стыке движение и ломается.

    }

    @ViewBuilder
    private var hintShape: some View {
        switch settings.hintStyle {
        case "line":
            Capsule()
                .fill(.white)
                .frame(width: 34, height: 3.5)
        case "dot":
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)
        default:
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
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


/// Рисует ли обложку общий слой поверх содержимого.
///
/// Карточке плеера в этом случае остаётся только оставить под неё место:
/// две одинаковые картинки в одном кадре — это мерцание на переходе.
private struct HeroArtworkKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var heroArtworkActive: Bool {
        get { self[HeroArtworkKey.self] }
        set { self[HeroArtworkKey.self] = newValue }
    }
}
