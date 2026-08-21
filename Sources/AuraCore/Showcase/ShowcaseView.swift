import SwiftUI

/// Витрина: плеер во весь экран.
///
/// Композиция строится от размера экрана, а не от жёстких чисел: на 13"
/// ноутбуке и на внешнем мониторе пропорции должны читаться одинаково.
struct ShowcaseView: View {
    let onClose: () -> Void

    @EnvironmentObject private var media: NowPlayingProvider
    @EnvironmentObject private var lyrics: LyricsProvider
    @EnvironmentObject private var settings: SettingsStore
    @State private var now = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        // Без `GeometryReader`.
        //
        // Он сообщал размер, который не совпадал с настоящим окном, и вся
        // витрина вместе с часами уезжала вниз на треть экрана. Центрирование
        // не должно зависеть от того, что кто-то измерил: растянутая рамка
        // ставит содержимое в середину сама, чем бы её ни наполнили.
        ZStack {
            background
            content

            // Часы и подсказка — слоями того же стека, а не наложением
            // поверх него. Наложение цепляется за внешнюю рамку, а та
            // оказывалась выше экрана, и оба слоя уезжали за край.
            if settings.showcaseClock {
                header
                    .padding(.leading, 64)
                    .padding(.top, 44)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Text(t("ui.e04ecaf6", "пробел — пауза · ← → трек · ↑ ↓ громкость · esc — закрыть"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.2))
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onReceive(clock) { now = $0 }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onClose)
        .background {
            // Кнопки-невидимки: витрина занимает весь экран, и обычный
            // onKeyPress до неё не доходит — фокус ей не принадлежит.
            VStack {
                Button("") { media.send(.togglePlayPause) }
                    .keyboardShortcut(.space, modifiers: [])
                Button("") { media.send(.next) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { media.send(.previous) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { SystemVolume.set(SystemVolume.current + 0.05) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("") { SystemVolume.set(SystemVolume.current - 0.05) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button("", action: onClose)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        }
    }

    // MARK: - Фон

    @ViewBuilder
    private var background: some View {
        ZStack {
            Color.black
            if settings.backgroundStyle == "gradient" {
                AuraTheme.gradient(settings.gradientPreset)
            } else if settings.backgroundStyle == "artwork",
                      let artwork = media.nowPlaying?.artwork {
                // `opaque: true` заставляло размытие брать краевые пиксели
                // и превращало обложку в огромное тёмное пятно посреди
                // экрана. Масштаб с запасом прячет мягкие края размытия,
                // которые иначе видны как круг.
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    // Растянуть сильно: квадратная обложка, размытая мягко,
                    // читается на широком экране как тёмный круг посередине.
                    .scaleEffect(2.6)
                    .blur(radius: 130)
                    .opacity(0.38)
                    .animation(.smooth(duration: 0.8), value: artwork)
            }
            LinearGradient(
                colors: [.black.opacity(0.35), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Композиция

    /// Композиция витрины.
    ///
    /// Размеры постоянные, а не вычисленные от экрана: витрина всегда
    /// открывается во весь экран, а обложка в треть его высоты на большом
    /// мониторе выглядит нелепо крупной.
    /// Двести шестьдесят, а не треть высоты экрана: вместе с текстом песни
    /// композиция должна помещаться и на тринадцатидюймовом ноутбуке,
    /// иначе часы и подсказка уезжают за край.
    private static let artworkSide: CGFloat = 260

    @ViewBuilder
    private var content: some View {
        if let playing = media.nowPlaying {
            composition(playing, artworkSide: Self.artworkSide)
                .frame(maxWidth: 1120)
                .padding(.horizontal, 64)
        } else {
            idle
        }
    }

    /// Два макета: колонками — обложка и текст рядом; по центру — всё
    /// вертикально.
    ///
    /// Пустая колонка текста больше не занимает места. Раньше она держала
    /// сто пятьдесят точек всегда, даже когда текста нет вовсе, — и сдвигала
    /// собой всю композицию.
    @ViewBuilder
    private func composition(
        _ playing: NowPlayingProvider.NowPlaying,
        artworkSide: CGFloat
    ) -> some View {
        if settings.showcaseLayout == "centered" {
            VStack(spacing: 22) {
                trackColumn(playing, width: artworkSide, alignment: .center)
                if hasLyrics(for: playing) {
                    lyricsColumn(playing, alignment: .center)
                }
            }
        } else {
            HStack(alignment: .center, spacing: 56) {
                trackColumn(playing, width: artworkSide)
                if hasLyrics(for: playing) {
                    lyricsColumn(playing, alignment: .leading)
                }
            }
        }
    }

    private func hasLyrics(for playing: NowPlayingProvider.NowPlaying) -> Bool {
        guard settings.showLyrics else { return false }
        let triple = lyrics.triple(at: playing.elapsedNow() ?? 0)
        return triple.current != nil || triple.next != nil || lyrics.isLoading
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 34, weight: .light, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .monospacedDigit()
            Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.28))
        }
    }

    // MARK: - Левая колонка: трек

    private func trackColumn(
        _ playing: NowPlayingProvider.NowPlaying,
        width: CGFloat,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 14) {
            artwork(playing.artwork, side: width)

            // Выравнивание берётся из макета, а не зашито влево: в режиме
            // «по центру» название и исполнитель прижимались к левому краю
            // колонки, и по центру оказывалась только обложка.
            VStack(alignment: alignment, spacing: 4) {
                Text(playing.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(playing.subtitle ?? playing.appName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .multilineTextAlignment(alignment == .center ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                progress(playing, at: context.date)
            }
            .frame(height: 32)

            controls(playing)
        }
        .frame(width: width, alignment: alignment == .center ? .center : .leading)
    }

    @ViewBuilder
    private func artwork(_ image: NSImage?, side: CGFloat) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.white.opacity(0.07))
                    .overlay {
                        Image(systemName: "waveform")
                            .font(.system(size: side * 0.18, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.3))
                    }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.07, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 36, y: 16)
    }

    @ViewBuilder
    private func progress(_ playing: NowPlayingProvider.NowPlaying, at date: Date) -> some View {
        if let value = playing.progress(at: date) {
            VStack(spacing: 7) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule()
                            .fill(AuraTheme.accent(for: playing.accent, settings: settings))
                            .frame(width: geometry.size.width * value)
                    }
                }
                .frame(height: 5)

                HStack {
                    Text(Self.time(playing.elapsedNow(at: date)))
                    Spacer()
                    Text(Self.time(playing.duration))
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .monospacedDigit()
            }
        }
    }

    private func controls(_ playing: NowPlayingProvider.NowPlaying) -> some View {
        HStack(spacing: 22) {
            button("backward.fill", size: 18) { media.send(.previous) }
            button(playing.isPlaying ? "pause.fill" : "play.fill", size: 24) {
                media.send(.togglePlayPause)
            }
            button("forward.fill", size: 18) { media.send(.next) }
        }
    }

    private func button(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: size + 26, height: size + 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Текст песни

    /// Прошедшая строка приглушена, текущая крупная и яркая, следующая едва
    /// намечена.
    ///
    /// Высота больше не задаётся заранее. Она задавалась, чтобы строки разной
    /// длины не дёргали композицию, — но платой было то, что пустая колонка
    /// занимала место всегда, даже когда текста нет. Вместо этого у каждой
    /// строки своя постоянная высота: композиция не дрожит, а пустоты нет.
    private func lyricsColumn(
        _ playing: NowPlayingProvider.NowPlaying,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            let position = playing.elapsedNow(at: context.date) ?? 0
            let triple = lyrics.triple(at: position)
            let centred = alignment == .center

            VStack(alignment: alignment, spacing: 12) {
                if triple.current != nil || triple.next != nil {
                    lyric(triple.previous, size: 19, opacity: 0.22, centred: centred)
                    lyric(triple.current, size: 30, opacity: 0.95,
                          weight: .semibold, centred: centred)
                    lyric(triple.next, size: 19, opacity: 0.22, centred: centred)
                } else if lyrics.isLoading {
                    Text(t("ui.1c05e73b", "ищем текст…"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.18))
                }
            }
            .frame(maxWidth: 560, alignment: centred ? .center : .leading)
            .multilineTextAlignment(centred ? .center : .leading)
            // Меняется строка, а не вся колонка: анимация на всём блоке
            // заставляла соседние строки ползать вместе с ней.
            .animation(.smooth(duration: 0.45), value: triple.current)
        }
        .frame(maxWidth: 560)
    }

    @ViewBuilder
    private func lyric(
        _ text: String?,
        size: CGFloat,
        opacity: Double,
        weight: Font.Weight = .medium,
        centred: Bool = false
    ) -> some View {
        Text(text ?? " ")
            .font(.system(size: size, weight: weight))
            .foregroundStyle(.white.opacity(text == nil ? 0 : opacity))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            // Постоянная высота строки: без неё смена короткой строки
            // на длинную двигает соседние.
            .frame(
                minHeight: size * 1.35,
                alignment: centred ? .center : .leading
            )
            .frame(maxWidth: .infinity, alignment: centred ? .center : .leading)
            // Новая строка не подменяет старую на месте, а проявляется:
            // подмена текста внутри одного вида читается как подёргивание.
            .id(text ?? "—")
            .transition(.opacity.combined(with: .offset(y: 8)))
    }

    private var idle: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 46, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.28))
            Text(t("ui.7eaefe89", "Ничего не играет"))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private static func time(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
