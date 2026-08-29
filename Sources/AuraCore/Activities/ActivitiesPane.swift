import AppKit
import SwiftUI

/// Вкладка «Активности» в раскрытой панели: всё, что сейчас живёт в вырезе,
/// плюс быстрый запуск таймера.
struct ActivitiesPane: View {
    /// Высота одной строки и шапки со счётчиком. Те же числа знает
    /// `NotchViewModel`, иначе расчёт панели разойдётся с разметкой.
    /// Высота строки списка.
    ///
    /// Список в раскрытом острове — это то, во что смотрят в упор, а не
    /// мельком: сорок две точки на строку с девятипунктовым текстом читались
    /// как мелкий шрифт в договоре.
    static let rowHeight: CGFloat = 52
    static let headerHeight: CGFloat = 22
    static let bannerHeight: CGFloat = 54

    @EnvironmentObject private var center: ActivityCenter
    @EnvironmentObject private var media: NowPlayingProvider
    @EnvironmentObject private var shelf: ShelfService
    @EnvironmentObject private var notifications: NotificationMirrorProvider

    private var accessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(t("ui.32f1084f", "Нет доступа к плееру"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text(t("ui.3c388255", "Разрешите Aura управлять им в «Конфиденциальность → Автоматизация»"))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(t("ui.616bb19d", "Разрешить")) {
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
        .padding(.horizontal, 11)
        .frame(height: Self.bannerHeight)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.14)))
    }

    /// Плеер показывается отдельной карточкой, поэтому в общий список не идёт.
    private var others: [Activity] {
        center.activities.filter { $0.id != "media.nowplaying" }
    }

    /// Сколько строк показываем, прежде чем свернуть остаток.
    ///
    /// Пять чатов — пять строк, а десять уже растянут остров во весь экран.
    /// Панель считает высоту по этому же числу, и лишние строки просто
    /// срезались нижней кромкой.
    static let maxRows = 5

    /// Строки, которые видно. Очередь активностей и так держит предел —
    /// здесь остаётся только не выйти за него самим.
    private var visible: [Activity] {
        Array(others.prefix(Self.maxRows))
    }

    /// Сколько осталось за пределом.
    private var hidden: Int {
        center.overflow + max(0, others.count - visible.count)
    }

    /// Итоговая строка: сколько ещё ждёт и от кого.
    private var moreRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 26)

            Text(String(format: t("ui.3a90c7e1", "ещё %d"), hidden))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))

            if let source = hiddenSource {
                Text(source)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 11)
        .frame(height: ActivitiesPane.rowHeight)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.04)))
    }

    /// Откуда остаток, если он весь из одного приложения.
    private var hiddenSource: String? {
        // Вытесненных активностей у нас на руках нет — очередь их не отдаёт.
        // Зато если всё, что видно, из одного приложения, остаток почти
        // наверняка оттуда же.
        let apps = Set(others.compactMap { NotificationMirrorProvider.appName(fromActivityID: $0.id) })
        return apps.count == 1 ? apps.first : nil
    }

    private var unreadCount: Int {
        notifications.unread.values.reduce(0, +)
    }

    /// Снять все значки разом. Иначе непрочитанное приходится разбирать
    /// по одному или открывать каждое приложение — а уведомления приходят
    /// пачками из трёх мессенджеров сразу.
    private var readAllButton: some View {
        Button(t("ui.3c17e082", "Прочитать всё")) {
            notifications.markAllRead()
        }
        .buttonStyle(.plain)
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.12)))
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

            // Плашки «пока тихо» здесь больше нет. Пустая панель по наведению
            // теперь и не раскрывается (см. NotchViewModel.hasContent), а
            // объяснять пользователю тишину надписью — занимать вырез тем,
            // ради чего на него не смотрят.
            if unreadCount > 0 {
                HStack(spacing: 6) {
                    Text("\(unreadCount)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .monospacedDigit()
                    Spacer(minLength: 4)
                    readAllButton
                }
                .frame(height: Self.headerHeight)
                .padding(.horizontal, 2)
            }

            // Ни прокрутки, ни распорки.
            //
            // Прокрутка внутри выреза — плохой обмен: чтобы её увидеть, нужно
            // уже смотреть в панель. А распорка делала содержимое жадным
            // по высоте, и измерить его настоящий размер становилось нечем.
            // Панель растёт под список, а не наоборот.
            if !others.isEmpty {
                VStack(spacing: 6) {
                    ForEach(visible) { activity in
                        ActivityRow(activity: activity) { dismiss(activity) }
                    }
                    if hidden > 0 { moreRow }
                }
            }

        }
    }

}

extension ActivitiesPane {
    /// Убрать активность из выреза.
    ///
    /// Для уведомления это «прочитал»: ждать, пока человек переключится
    /// в приложение, не обязательно. Для всего остального — просто убрать,
    /// и провайдер не поставит своё обратно: загрузка, которую свернули
    /// руками, возвращалась на следующем же опросе.
    private func dismiss(_ activity: Activity) {
        // Прочитан один разговор, а не всё приложение: у каждого чата
        // своя строка, и убирается она отдельно.
        if let thread = NotificationMirrorProvider.thread(fromActivityID: activity.id) {
            notifications.markThreadRead(thread)
        } else {
            center.dismiss(id: activity.id)
        }
    }
}

private struct ActivityRow: View {
    let activity: Activity
    var onDismiss: () -> Void = {}

    var body: some View {
        content
            .modifier(FileActions(url: activity.fileURL, onDismiss: onDismiss))
            .contextMenu {
                Button(t("ui.0a7c3e58", "Убрать"), action: onDismiss)
            }
    }

    private var content: some View {
        HStack(spacing: 11) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                if let subtitle = activity.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            switch activity.indicator {
            case .progress(let value):
                ProgressRing(progress: value, tint: activity.tint)
                    .frame(width: 19, height: 19)
            case .text(let text):
                UnreadPill(text: text, tint: activity.tint)
            case .pulse:
                PulsingDot(tint: activity.tint)
            case .audioBars:
                AudioBars(tint: activity.tint)
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 9)
        // Постоянная высота строки. Панель считает свою высоту заранее,
        // и если строка окажется выше расчёта — низ списка просто срежется
        // краем панели. Лучше одинаковые строки, чем обрезанный список.
        .frame(height: ActivitiesPane.rowHeight)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [activity.title, activity.subtitle].compactMap { $0 }.joined(separator: ", ")
        )
    }

    @ViewBuilder
    private var icon: some View {
        if let artwork = activity.artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            Image(systemName: activity.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(activity.tint)
                .frame(width: 26)
        }
    }
}

/// Карточку с файлом можно открыть кликом и перетащить мышью прямо в другое
/// приложение — снимок экрана уезжает в письмо, не заходя в папку.
private struct FileActions: ViewModifier {
    let url: URL?
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        if let url {
            // У строки с файлом клик уже занят открытием — убрать её можно
            // через контекстное меню.
            content
                .onTapGesture { NSWorkspace.shared.open(url) }
                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                .help(url.path)
        } else {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
        }
    }
}
