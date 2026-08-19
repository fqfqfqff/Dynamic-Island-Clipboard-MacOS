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
        GeometryReader { geometry in
            ZStack {
                background
                content(in: geometry.size)
            }
        }
        .ignoresSafeArea()
        .onReceive(clock) { now = $0 }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onClose)
        .background {
            Button("", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
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
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 140, opaque: true)
                    .opacity(0.5)
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

    private func content(in size: CGSize) -> some View {
        // Обложка занимает примерно треть высоты, но не разрастается
        // на больших мониторах до нелепых размеров.
        let artworkSide = min(340, max(200, size.height * 0.34))
        let horizontalPadding = max(48, size.width * 0.06)

        // Композиция живёт ровно в центре экрана; часы и подсказка лежат
        // отдельными слоями поверх, чтобы не смещать её собой.
        return Group {
            if let playing = media.nowPlaying {
                composition(playing, artworkSide: artworkSide)
                    .frame(maxWidth: min(1120, size.width - horizontalPadding * 2))
            } else {
                idle
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .overlay(alignment: .topLeading) {
            if settings.showcaseClock {
                header
                    .padding(.leading, horizontalPadding)
                    .padding(.top, max(28, size.height * 0.05))
            }
        }
        .overlay(alignment: .bottom) {
            Text("двойной клик или esc — закрыть")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.2))
                .padding(.bottom, 28)
        }
    }

    /// Два макета: колонками — обложка и текст рядом; по центру — всё
    /// вертикально, текст под треком.
    @ViewBuilder
    private func composition(
        _ playing: NowPlayingProvider.NowPlaying,
        artworkSide: CGFloat
    ) -> some View {
        if settings.showcaseLayout == "centered" {
            VStack(spacing: 26) {
                trackColumn(playing, width: artworkSide, alignment: .center)
                lyricsColumn(playing, height: 150, alignment: .center)
            }
        } else {
            HStack(alignment: .top, spacing: 56) {
                trackColumn(playing, width: artworkSide)
                lyricsColumn(playing, height: artworkSide)
            }
        }
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
        VStack(alignment: alignment, spacing: 18) {
            artwork(playing.artwork, side: width)

            VStack(alignment: .leading, spacing: 4) {
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

    // MARK: - Правая колонка: текст песни

    /// Прошедшая строка приглушена, текущая крупная и яркая, следующая едва
    /// намечена. Высота колонки задана заранее — иначе строки разной длины
    /// дёргали бы всю композицию по вертикали.
    private func lyricsColumn(
        _ playing: NowPlayingProvider.NowPlaying,
        height: CGFloat,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            let position = playing.elapsedNow(at: context.date) ?? 0
            let triple = lyrics.triple(at: position)
            let hasLyrics = triple.current != nil || triple.next != nil

            VStack(alignment: alignment, spacing: 20) {
                Spacer(minLength: 0)
                if hasLyrics {
                    lyric(triple.previous, size: 22, opacity: 0.25)
                    lyric(triple.current, size: 36, opacity: 0.96, weight: .bold)
                    lyric(triple.next, size: 22, opacity: 0.25)
                } else {
                    Text(lyrics.isLoading ? "ищем текст…" : "текста нет")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.14))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 520, alignment: alignment == .center ? .center : .leading)
            .multilineTextAlignment(alignment == .center ? .center : .leading)
            .animation(.smooth(duration: 0.4), value: triple.current)
        }
        .frame(
            maxWidth: 520,
            minHeight: height,
            maxHeight: height,
            alignment: alignment == .center ? .center : .leading
        )
    }

    @ViewBuilder
    private func lyric(
        _ text: String?,
        size: CGFloat,
        opacity: Double,
        weight: Font.Weight = .medium
    ) -> some View {
        Text(text ?? " ")
            .font(.system(size: size, weight: weight))
            .foregroundStyle(.white.opacity(text == nil ? 0 : opacity))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var idle: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 46, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.28))
            Text("Ничего не играет")
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
