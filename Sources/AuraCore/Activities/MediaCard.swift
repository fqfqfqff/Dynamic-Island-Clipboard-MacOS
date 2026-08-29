import AppKit
import SwiftUI

/// Плеер в раскрытом вырезе.
struct MediaCard: View {
    @EnvironmentObject private var media: NowPlayingProvider
    @EnvironmentObject private var settings: SettingsStore
    /// Обложку может рисовать общий слой острова — тогда она переезжает
    /// из компактного слота, а не появляется здесь заново.
    @Environment(\.heroArtworkActive) private var heroArtworkActive
    @EnvironmentObject private var modifiers: ModifierWatcher
    /// Подтверждение показываем на месте исполнителя: отдельная плашка
    /// в вырезе размером с ноготь — это перебор.
    @State private var didCopy = false
    /// Куда пользователь ведёт палец по полосе, 0…1. Пока ведёт — плеер
    /// не трогаем: перемотка на каждое движение это десяток запросов
    /// к плееру и рывками едущая полоса.
    @State private var scrubbing: Double?

    private var accent: Color {
        AuraTheme.accent(for: media.nowPlaying?.accent ?? .pink, settings: settings)
    }

    private var design: Font.Design {
        AuraTheme.design(settings.fontDesign)
    }

    /// Сторона обложки в компактном макете.
    static let compactArtwork: CGFloat = 62

    /// Сторона обложки в текущем макете.
    private var artworkSide: CGFloat {
        settings.playerLayout == "compact" ? Self.compactArtwork : settings.artworkSize
    }

    var body: some View {
        if let playing = media.nowPlaying {
            if settings.playerLayout == "compact" {
                compactBody(playing)
            } else {
                largeBody(playing)
            }
        }
    }

    @ViewBuilder
    private func largeBody(_ playing: NowPlayingProvider.NowPlaying) -> some View {
        Group {
            VStack(spacing: 6) {
                artwork(playing)

                VStack(spacing: 1) {
                    MarqueeText(
                        text: playing.title,
                        font: .system(size: settings.titleFontSize, weight: .bold, design: design),
                        color: .white
                    )
                    .frame(height: settings.titleFontSize + 6)

                    // Исполнителя тоже катаем: у дуэтов и сборников имя
                    // не влезает ничуть не реже, чем название.
                    MarqueeText(
                        text: secondLine(playing),
                        font: .system(
                            size: max(9, settings.titleFontSize - 3.5),
                            weight: .medium,
                            design: design
                        ),
                        color: .white.opacity(didCopy ? 0.85 : 0.55)
                    )
                    .frame(height: max(9, settings.titleFontSize - 3.5) + 5)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { copy(playing) }
                .help(t("ui.ee1d0a37", "Нажмите, чтобы скопировать название"))
                .animation(AuraAnimation.content, value: playing.title)

                // Полоса и кнопки — один блок: между ними почти нет зазора,
                // управление читается как часть дорожки.
                VStack(spacing: 2) {
                    if settings.showSeekBar {
                        // Полоса идёт по часам между опросами — иначе она стоит
                        // на месте и дёргается раз в несколько секунд. На паузе
                        // двигать нечего: там достаточно одного кадра.
                        Group {
                            if playing.isPlaying {
                                TimelineView(.periodic(from: .now, by: 0.2)) { context in
                                    seekBar(playing, at: context.date)
                                }
                            } else {
                                seekBar(playing, at: .now)
                            }
                        }
                        .frame(height: 26)
                    }

                    if settings.showControls {
                        controls(playing)
                    }
                }
            }
            .padding(.horizontal, 10)
        }
    }

    /// Компактный макет: обложка слева, название и полоса справа.
    ///
    /// Крупный макет отдаёт под обложку двести с лишним точек, и раскрытый
    /// остров закрывает треть экрана. Здесь та же карточка втрое ниже,
    /// а читается не хуже: строка названия остаётся полной ширины.
    @ViewBuilder
    private func compactBody(_ playing: NowPlayingProvider.NowPlaying) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                artwork(playing)

                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(
                        text: playing.title,
                        font: .system(size: settings.titleFontSize, weight: .bold, design: design),
                        color: .white,
                        alignment: .leading
                    )
                    .frame(height: settings.titleFontSize + 6)

                    MarqueeText(
                        text: secondLine(playing),
                        font: .system(
                            size: max(9, settings.titleFontSize - 3.5),
                            weight: .medium,
                            design: design
                        ),
                        color: .white.opacity(didCopy ? 0.85 : 0.55),
                        alignment: .leading
                    )
                    .frame(height: max(9, settings.titleFontSize - 3.5) + 5)

                    if settings.showSeekBar {
                        Group {
                            if playing.isPlaying {
                                TimelineView(.periodic(from: .now, by: 0.2)) { context in
                                    seekBar(playing, at: context.date)
                                }
                            } else {
                                seekBar(playing, at: .now)
                            }
                        }
                        .frame(height: 26)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { copy(playing) }
                .help(t("ui.ee1d0a37", "Нажмите, чтобы скопировать название"))
                .animation(AuraAnimation.content, value: playing.title)
            }

            if settings.showControls { controls(playing) }
        }
        .padding(.horizontal, 10)
    }

    /// Вторая строка карточки.
    ///
    /// По нажатой ⌥ она показывает то, чего в вырезе обычно нет места
    /// показывать: альбом и откуда играет. Отдельной строки под это нет
    /// намеренно — панель и так растёт по содержимому.
    private func secondLine(_ playing: NowPlayingProvider.NowPlaying) -> String {
        if didCopy { return t("ui.9c2b5e70", "Скопировано") }

        if modifiers.isOptionDown {
            let parts = [playing.album, playing.appName].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
        }
        return playing.subtitle ?? playing.appName
    }

    /// «Исполнитель — Трек» в буфер: этим делятся чаще всего, а
    /// перепечатывать с экрана неудобно.
    private func copy(_ playing: NowPlayingProvider.NowPlaying) {
        let line = [playing.subtitle, playing.title]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " — ")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)

        withAnimation(AuraAnimation.content) { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(AuraAnimation.content) { didCopy = false }
        }
    }

    // MARK: - Обложка

    @ViewBuilder
    private func artwork(_ playing: NowPlayingProvider.NowPlaying) -> some View {
        if heroArtworkActive {
            Color.clear
                .frame(width: artworkSide, height: artworkSide)
        } else {
            ownArtwork(playing)
        }
    }

    @ViewBuilder
    private func ownArtwork(_ playing: NowPlayingProvider.NowPlaying) -> some View {
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
        .frame(width: artworkSide, height: artworkSide)
        .clipShape(RoundedRectangle(cornerRadius: settings.artworkCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: settings.artworkCornerRadius, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: accent.opacity(0.35), radius: 18, y: 8)
        .animation(AuraAnimation.content, value: playing.artwork)
    }

    // MARK: - Длительность

    @ViewBuilder
    private func seekBar(_ playing: NowPlayingProvider.NowPlaying, at date: Date) -> some View {
        if let progress = playing.progress(at: date) {
            // Пока ведут пальцем — полоса слушается пальца, а не плеера.
            let shown = scrubbing ?? progress
            let elapsed = scrubbing.map { (playing.duration ?? 0) * $0 }
                ?? playing.elapsedNow(at: date)

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
                            .frame(width: max(0, geometry.size.width * shown))

                        // Ручка появляется только на время ведения: в покое
                        // она превращает полосу в элемент управления, которым
                        // пользуются раз в десять треков.
                        if scrubbing != nil {
                            Circle()
                                .fill(.white)
                                .frame(width: 11, height: 11)
                                .shadow(color: .black.opacity(0.4), radius: 3)
                                .offset(x: max(0, geometry.size.width * shown - 5.5))
                        }
                    }
                    .contentShape(Rectangle().inset(by: -8))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                scrubbing = min(1, max(0, value.location.x / geometry.size.width))
                            }
                            .onEnded { value in
                                let share = min(1, max(0, value.location.x / geometry.size.width))
                                scrubbing = nil
                                guard let duration = playing.duration, duration > 0 else { return }
                                media.seek(to: duration * share)
                            }
                    )
                }
                .frame(height: 6)
                .animation(AuraAnimation.touch, value: scrubbing != nil)

                HStack {
                    Text(Self.time(elapsed))
                        .foregroundStyle(.white.opacity(scrubbing == nil ? 0.45 : 0.9))
                    Spacer()
                    if settings.showRemainingTime, let duration = playing.duration {
                        Text("-" + Self.time(duration - (elapsed ?? 0)))
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
            .accessibilityLabel(t("ui.2f4b9e05", "Предыдущий трек"))

            Button { media.send(.togglePlayPause) } label: {
                Image(systemName: playing.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black.opacity(0.88))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(accent))
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(
                playing.isPlaying
                    ? t("ui.83c1f720", "Пауза")
                    : t("ui.d05b3e18", "Играть")
            )
            .buttonStyle(PressableButtonStyle(pressedScale: 0.9, hoverScale: 1.08))

            Button { media.send(.next) } label: {
                icon("forward.fill", size: 15)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(t("ui.6c30a4b1", "Следующий трек"))
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
