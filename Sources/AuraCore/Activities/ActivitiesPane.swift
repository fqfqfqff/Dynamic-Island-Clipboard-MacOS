import AppKit
import SwiftUI

/// Вкладка «Активности» в раскрытой панели: всё, что сейчас живёт в вырезе,
/// плюс быстрый запуск таймера.
struct ActivitiesPane: View {
    @EnvironmentObject private var center: ActivityCenter
    @EnvironmentObject private var media: NowPlayingProvider
    @EnvironmentObject private var shelf: ShelfService

    private var accessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Нет доступа к плееру")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Разрешите Aura управлять им в «Конфиденциальность → Автоматизация»")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button("Разрешить") {
                if let url = URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                ) {
                    NSWorkspace.shared.open(url)
                }
                media.retryAccess()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.14)))
    }

    /// Плеер показывается отдельной карточкой, поэтому в общий список не идёт.
    private var others: [Activity] {
        center.activities.filter { $0.id != "media.nowplaying" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if media.accessDenied {
                accessBanner
            }

            if media.nowPlaying != nil {
                MediaCard()
            }

            if !shelf.items.isEmpty {
                ShelfPane()
            }

            // Плашка «тихо» уместна, только когда показывать действительно
            // нечего: раньше она вылезала под плеером, потому что условия
            // проверялись независимо друг от друга.
            if media.nowPlaying == nil && others.isEmpty && shelf.items.isEmpty {
                PlaceholderPane(
                    symbol: "waveform",
                    title: "Пока тихо",
                    subtitle: "Включите музыку, смените громкость или сделайте снимок экрана"
                )
            } else if !others.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(others) { activity in
                            ActivityRow(activity: activity)
                        }
                    }
                }
            } else {
                Spacer(minLength: 0)
            }

        }
    }

}

private struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        content
            .modifier(FileActions(url: activity.fileURL))
    }

    private var content: some View {
        HStack(spacing: 9) {
            icon

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                if let subtitle = activity.subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.45))
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 4)

            switch activity.indicator {
            case .progress(let value):
                ProgressRing(progress: value, tint: activity.tint)
                    .frame(width: 16, height: 16)
            case .text(let text):
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(activity.tint)
                    .monospacedDigit()
            case .pulse:
                PulsingDot(tint: activity.tint)
            case .audioBars:
                AudioBars(tint: activity.tint)
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06)))
    }

    @ViewBuilder
    private var icon: some View {
        if let artwork = activity.artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: activity.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(activity.tint)
                .frame(width: 20)
        }
    }
}

/// Карточку с файлом можно открыть кликом и перетащить мышью прямо в другое
/// приложение — снимок экрана уезжает в письмо, не заходя в папку.
private struct FileActions: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        if let url {
            content
                .onTapGesture { NSWorkspace.shared.open(url) }
                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                .help(url.path)
        } else {
            content
        }
    }
}
