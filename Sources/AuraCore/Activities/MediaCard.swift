import SwiftUI

/// Плеер в раскрытом вырезе.
struct MediaCard: View {
    @EnvironmentObject private var media: NowPlayingProvider
    @EnvironmentObject private var settings: SettingsStore
    @State private var artworkPulse = false

    private var accent: Color {
        AuraTheme.accent(for: media.nowPlaying?.accent ?? .pink, settings: settings)
    }

    private var design: Font.Design {
        AuraTheme.design(settings.fontDesign)
    }

    var body: some View {
        if let playing = media.nowPlaying {
            VStack(spacing: 6) {
                artwork(playing)

                VStack(spacing: 1) {
                    Text(playing.title)
                        .font(.system(size: settings.titleFontSize, weight: .bold, design: design))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .contentTransition(.opacity)

                    Text(playing.subtitle ?? playing.appName)
                        .font(.system(size: max(9, settings.titleFontSize - 3.5), weight: .medium, design: design))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity)
                .animation(AuraAnimation.content, value: playing.title)

                // Полоса и кнопки — один блок: между ними почти нет зазора,
                // управление читается как часть дорожки.
                VStack(spacing: 2) {
                    if settings.showSeekBar {
                        // Полоса идёт по часам между опросами — иначе она стоит
                        // на месте и дёргается раз в несколько секунд.
                        TimelineView(.periodic(from: .now, by: 0.2)) { context in
                            seekBar(playing, at: context.date)
                        }
                        .frame(height: 26)
                    }

                    if settings.showControls {
                        controls(playing)
                    }
                }
            }
            .padding(.horizontal, 10)
            .onChange(of: playing.title) { _, _ in
                // Смена трека отзывается лёгким «вдохом» обложки.
                artworkPulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { artworkPulse = false }
            }
        }
    }

    // MARK: - Обложка

    @ViewBuilder
    private func artwork(_ playing: NowPlayingProvider.NowPlaying) -> some View {
        Group {
            if let image = playing.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "waveform")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.white.opacity(0.4))
                    }
            }
        }
        .frame(width: settings.artworkSize, height: settings.artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: settings.artworkCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: settings.artworkCornerRadius, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: accent.opacity(0.35), radius: 18, y: 8)
        .scaleEffect(artworkPulse ? 1.05 : 1)
        .animation(AuraAnimation.touch, value: artworkPulse)
        .animation(AuraAnimation.content, value: playing.artwork)
    }

    // MARK: - Длительность

    @ViewBuilder
    private func seekBar(_ playing: NowPlayingProvider.NowPlaying, at date: Date) -> some View {
        if let progress = playing.progress(at: date) {
            VStack(spacing: 5) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.85), accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geometry.size.width * progress))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { point in
                        guard let duration = playing.duration, duration > 0 else { return }
                        media.seek(to: duration * min(1, max(0, point.x / geometry.size.width)))
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(Self.time(playing.elapsedNow(at: date)))
                    Spacer()
                    if settings.showRemainingTime, let duration = playing.duration {
                        Text("-" + Self.time(duration - (playing.elapsedNow(at: date) ?? 0)))
                    } else {
                        Text(Self.time(playing.duration))
                    }
                }
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .monospacedDigit()
            }
        } else {
            // Длительность известна не всем источникам — у видео в браузере её
            // нет. Тогда на месте полосы живут полоски частот, без подписей.
            AudioBars(tint: accent, barCount: settings.barCount)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Управление

    private func controls(_ playing: NowPlayingProvider.NowPlaying) -> some View {
        HStack(spacing: 18) {
            Button { media.send(.previous) } label: {
                icon("backward.fill", size: 15)
            }
            .buttonStyle(PressableButtonStyle())

            Button { media.send(.togglePlayPause) } label: {
                Image(systemName: playing.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black.opacity(0.88))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(accent))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.9, hoverScale: 1.08))

            Button { media.send(.next) } label: {
                icon("forward.fill", size: 15)
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    private func icon(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }

    private static func time(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
