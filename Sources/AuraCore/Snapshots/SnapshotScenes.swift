import AppKit
import SwiftUI

/// Сцены для снимков: подставные данные вместо живых провайдеров.
///
/// Данные собираются здесь, а не в тесте, чтобы снимок и приложение
/// показывали одни и те же виды — иначе снимки перестают о чём-либо
/// свидетельствовать.
@MainActor
public enum SnapshotScenes {

    // MARK: - Окружение

    /// Настройки на отдельном домене: снимки не должны зависеть от того,
    /// что пользователь накрутил себе, и не должны это менять.
    static func freshSettings() -> SettingsStore {
        let suite = "dev.kekch.aura.snapshots"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    /// Геометрия настоящего экрана, если он есть: снимок должен совпадать
    /// с тем, что видно на этой машине, а не с усреднённым макбуком.
    static func geometry(settings: SettingsStore) -> NotchGeometry {
        if let screen = ScreenGeometry.preferredScreen() {
            return ScreenGeometry.geometry(for: screen, settings: settings)
        }
        return ScreenGeometry.fallbackGeometry()
    }

    struct Environment {
        let settings: SettingsStore
        let viewModel: NotchViewModel
        let activities: ActivityCenter
        let media: NowPlayingProvider
        let spectrum: AudioSpectrumMonitor
        let lyrics: LyricsProvider
        let shelf: ShelfService
        let notifications: NotificationMirrorProvider
        let modifiers: ModifierWatcher
    }

    static func environment() -> Environment {
        let settings = freshSettings()
        let activities = ActivityCenter()
        let lyrics = LyricsProvider()
        let media = NowPlayingProvider(center: activities, settings: settings, lyrics: lyrics)
        let viewModel = NotchViewModel(geometry: geometry(settings: settings), settings: settings)
        return Environment(
            settings: settings,
            viewModel: viewModel,
            activities: activities,
            media: media,
            spectrum: AudioSpectrumMonitor(),
            lyrics: lyrics,
            shelf: ShelfService(),
            notifications: NotificationMirrorProvider(center: activities, settings: settings),
            modifiers: ModifierWatcher()
        )
    }

    /// Диагностика: с какой геометрией собираются сцены.
    public static func probeEnvironment() -> (CGRect, CGRect, CGFloat, CGSize) {
        let env = environment()
        return (
            env.viewModel.geometry.screenFrame,
            env.viewModel.geometry.notchRect,
            env.viewModel.geometry.menuBarHeight,
            env.viewModel.contentSize
        )
    }

    // MARK: - Подставные данные

    /// Обложка рисуется программно: снимки не должны тянуть за собой файлы.
    static func artwork(side: CGFloat = 220) -> NSImage {
        let image = NSImage(size: CGSize(width: side, height: side))
        image.lockFocus()
        NSGradient(
            colors: [
                NSColor(srgbRed: 0.98, green: 0.24, blue: 0.42, alpha: 1),
                NSColor(srgbRed: 0.42, green: 0.16, blue: 0.72, alpha: 1),
            ]
        )?.draw(in: CGRect(x: 0, y: 0, width: side, height: side), angle: -45)

        NSColor(white: 1, alpha: 0.18).setFill()
        NSBezierPath(ovalIn: CGRect(x: side * 0.28, y: side * 0.28, width: side * 0.44, height: side * 0.44)).fill()
        NSColor(white: 0, alpha: 0.35).setFill()
        NSBezierPath(ovalIn: CGRect(x: side * 0.45, y: side * 0.45, width: side * 0.1, height: side * 0.1)).fill()
        image.unlockFocus()
        return image
    }

    static func nowPlaying() -> NowPlayingProvider.NowPlaying {
        let cover = artwork()
        return NowPlayingProvider.NowPlaying(
            title: "Midnight City",
            subtitle: "M83",
            appName: "Spotify",
            artwork: cover,
            blurredArtwork: cover.blurred(radius: 26),
            duration: 243,
            elapsed: 97,
            elapsedAt: .now,
            isPlaying: true,
            accent: cover.accentColor,
            canControl: true
        )
    }

    static func mediaActivity() -> Activity {
        Activity(
            id: "media.nowplaying",
            title: "Midnight City",
            subtitle: "M83",
            symbol: "waveform",
            tint: artwork().accentColor,
            artwork: artwork(),
            priority: .ambient,
            indicator: .audioBars
        )
    }

    static func sideActivities() -> [Activity] {
        [
            Activity(
                id: "battery",
                title: "Зарядка",
                subtitle: "осталось 1 ч 20 мин",
                symbol: "battery.75",
                tint: .green,
                priority: .normal,
                indicator: .text("78%")
            ),
            Activity(
                id: "screenshot",
                title: "Снимок экрана",
                subtitle: "Снимок 2026-08-21 в 10.42.png",
                symbol: "camera.viewfinder",
                tint: .cyan,
                priority: .normal,
                indicator: .none
            ),
            Activity(
                id: "external.build",
                title: "Сборка проекта",
                subtitle: "swift build",
                symbol: "hammer.fill",
                tint: .orange,
                priority: .normal,
                indicator: .progress(0.62)
            ),
        ]
    }

    // MARK: - Холст

    /// Обои под островом: на чёрном фоне чёрную пилюлю не разглядеть,
    /// а именно её форму и надо проверять.
    static func wallpaper(height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.16, blue: 0.28),
                    Color(red: 0.35, green: 0.24, blue: 0.42),
                    Color(red: 0.62, green: 0.38, blue: 0.36),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Полоса строки меню: по ней видно, как остров с ней стыкуется.
            HStack {
                Text("Finder")
                    .font(.system(size: 13, weight: .semibold))
                Text("Файл")
                    .font(.system(size: 13))
                Spacer()
                Text("21 авг 10:42")
                    .font(.system(size: 13))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(height: height)
        }
    }

    static func canvas<Content: View>(
        size: CGSize,
        menuBarHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> AnyView {
        AnyView(
            ZStack(alignment: .top) {
                wallpaper(height: menuBarHeight)
                content()
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        )
    }

    // MARK: - Сцены

    public static func all() -> [SnapshotScene] {
        [
            collapsedEmpty(),
            collapsedMusic(),
            peek(),
            expandedMusic(),
            expandedActivities(),
            notificationEvent(),
            expandedWithoutMedia(),
            peekHint(),
            notificationBadge(),
            notificationThreads(),
            longNames(),
            showcaseColumns(),
            showcaseCentered(),
        ]
    }

    static func island(_ environment: Environment) -> some View {
        NotchRootView()
            .environmentObject(environment.viewModel)
            .environmentObject(environment.activities)
            .environmentObject(environment.media)
            .environmentObject(environment.settings)
            .environmentObject(environment.spectrum)
            .environmentObject(environment.lyrics)
            .environmentObject(environment.shelf)
            .environmentObject(environment.notifications)
            .environmentObject(environment.modifiers)
    }

    static func scene(
        _ name: String,
        size: CGSize,
        configure: (Environment) -> Void
    ) -> SnapshotScene {
        let environment = environment()
        configure(environment)

        // Состав содержимого в приложении приходит в модель подпиской из
        // контроллера. Сцена собирает окружение сама, и если это забыть,
        // панель молча схлопывается до минимальной высоты — так уже было.
        // Поэтому флаги выводятся здесь, а не расставляются в каждой сцене.
        let others = environment.activities.activities
            .filter { $0.id != "media.nowplaying" }
        environment.viewModel.hasMedia = environment.media.nowPlaying != nil
        environment.viewModel.hasShelf = !environment.shelf.items.isEmpty
        environment.viewModel.extraRowCount = others.count
        environment.viewModel.hasContent = environment.media.nowPlaying != nil
            || !environment.activities.activities.isEmpty
            || !environment.shelf.items.isEmpty

        return SnapshotScene(
            name: name,
            size: size,
            content: canvas(
                size: size,
                menuBarHeight: environment.viewModel.geometry.menuBarHeight
            ) {
                island(environment)
            }
        )
    }

    static let compactCanvas = CGSize(width: 760, height: 150)
    static let expandedCanvas = CGSize(width: 760, height: 580)

    static func collapsedEmpty() -> SnapshotScene {
        scene("01-collapsed-empty", size: compactCanvas) { _ in }
    }

    static func collapsedMusic() -> SnapshotScene {
        scene("02-collapsed-music", size: compactCanvas) { environment in
            environment.media.inject(nowPlaying())
            environment.activities.upsert(mediaActivity())
            environment.viewModel.compactAccessoryWidth = environment.settings.accessorySlotWidth * 2
        }
    }

    /// Подсказка-стрелка: показывать нечего, остров только подрос.
    static func peekHint() -> SnapshotScene {
        scene("08-peek-hint", size: compactCanvas) { environment in
            environment.viewModel.state = .peek
        }
    }

    static func peek() -> SnapshotScene {
        scene("03-peek", size: compactCanvas) { environment in
            environment.media.inject(nowPlaying())
            environment.activities.upsert(mediaActivity())
            environment.viewModel.compactAccessoryWidth = environment.settings.accessorySlotWidth * 2
            environment.viewModel.state = .peek
        }
    }

    static func expandedMusic() -> SnapshotScene {
        scene("04-expanded-music", size: expandedCanvas) { environment in
            environment.media.inject(nowPlaying())
            environment.activities.upsert(mediaActivity())
            environment.viewModel.state = .expanded
        }
    }

    /// Подставная иконка приложения: снимки не должны зависеть от того,
    /// что установлено на машине.
    static func appIcon() -> NSImage {
        let side: CGFloat = 128
        let image = NSImage(size: CGSize(width: side, height: side))
        image.lockFocus()
        NSGradient(colors: [
            NSColor(srgbRed: 0.24, green: 0.66, blue: 0.94, alpha: 1),
            NSColor(srgbRed: 0.10, green: 0.44, blue: 0.82, alpha: 1),
        ])?.draw(in: CGRect(x: 0, y: 0, width: side, height: side), angle: -90)
        NSColor.white.setFill()
        let plane = NSBezierPath()
        plane.move(to: CGPoint(x: side * 0.22, y: side * 0.52))
        plane.line(to: CGPoint(x: side * 0.80, y: side * 0.74))
        plane.line(to: CGPoint(x: side * 0.56, y: side * 0.28))
        plane.line(to: CGPoint(x: side * 0.46, y: side * 0.46))
        plane.close()
        plane.fill()
        image.unlockFocus()
        return image
    }

    /// Панель, когда музыки нет: раньше она была той же высоты и наполовину
    /// пустой.
    static func expandedWithoutMedia() -> SnapshotScene {
        scene("07-expanded-no-media", size: expandedCanvas) { environment in
            for activity in sideActivities().prefix(2) {
                environment.activities.upsert(activity)
            }
            environment.viewModel.state = .expanded
        }
    }

    /// Что остаётся в вырезе после карточки: значок приложения слева,
    /// число непрочитанных справа.
    static func notificationBadge() -> SnapshotScene {
        scene("09-notification-badge", size: compactCanvas) { environment in
            let icon = appIcon()
            environment.activities.upsert(
                Activity(
                    id: "notification.Telegram",
                    title: "Alex Rivera",
                    subtitle: "Голосовое сообщение",
                    symbol: "waveform.circle.fill",
                    tint: .white,
                    artwork: icon,
                    priority: .important,
                    indicator: .text("3")
                )
            )
            environment.viewModel.compactAccessoryWidth = environment.settings.accessorySlotWidth * 2
        }
    }

    /// Несколько чатов одного мессенджера: у каждого своя строка.
    /// Пятеро написали — это пять дел, а не «5» на значке приложения.
    static func notificationThreads() -> SnapshotScene {
        scene("11-notification-threads", size: expandedCanvas) { environment in
            let icon = appIcon()
            let chats: [(String, String, String)] = [
                ("Мама", "Позвони, как освободишься", "2"),
                ("Рабочий чат", "Голосовое сообщение", "5"),
                ("Alex Rivera", "Кружок", "1"),
            ]
            for (sender, text, count) in chats {
                environment.activities.upsert(
                    Activity(
                        id: "notification." + NotificationMirrorProvider.threadKey(
                            app: "Telegram", sender: sender
                        ),
                        title: sender,
                        subtitle: text,
                        symbol: "message.fill",
                        tint: .white,
                        artwork: icon,
                        priority: .important,
                        indicator: .text(count)
                    )
                )
            }
            environment.viewModel.state = .expanded
        }
    }

    static func notificationEvent() -> SnapshotScene {
        scene("06-notification", size: compactCanvas) { environment in
            let icon = appIcon()
            environment.notifications.inject(
                NotificationMirrorProvider.Message(
                    id: UUID(),
                    app: "Telegram",
                    bundleID: "ru.keepcoder.Telegram",
                    // Имя выдуманное: снимки уезжают в README, и своё
                    // имя там ни к чему.
                    sender: "Alex Rivera",
                    body: nil,
                    kind: .voice,
                    icon: icon,
                    tint: icon.accentColor,
                    receivedAt: .now
                )
            )
            environment.notifications.injectUnread(
                app: "Telegram", count: 3, sender: "Alex Rivera"
            )
            environment.viewModel.state = .event
        }
    }

    /// Длинные имена: они не влезают и должны ехать по кругу, а не
    /// обрываться многоточием.
    static func longNames() -> SnapshotScene {
        scene("10-long-names", size: expandedCanvas) { environment in
            var playing = nowPlaying()
            playing.title = "Everything In Its Right Place (Remastered 2016)"
            playing.subtitle = "Thom Yorke, Jonny Greenwood и Лондонский оркестр"
            environment.media.inject(playing)
            environment.activities.upsert(mediaActivity())
            environment.viewModel.state = .expanded
        }
    }

    // MARK: - Витрина

    static let showcaseCanvas = CGSize(width: 1280, height: 800)

    static func showcase(_ name: String, layout: String) -> SnapshotScene {
        let environment = environment()
        environment.settings.showcaseLayout = layout
        environment.settings.showLyrics = true
        environment.settings.showcaseClock = true
        var playing = nowPlaying()
        playing.fullArtwork = artwork(side: 640)
        environment.media.inject(playing)
        environment.lyrics.inject([
            .init(time: 0, text: "Waiting in the car"),
            .init(time: 90, text: "Waiting for a ride in the dark"),
            .init(time: 120, text: "The night city grows"),
            .init(time: 150, text: "Look and see her eyes"),
        ])

        return SnapshotScene(
            name: name,
            size: showcaseCanvas,
            settleTime: 0.7,
            content: AnyView(
                ShowcaseView(onClose: {})
                    .environmentObject(environment.media)
                    .environmentObject(environment.lyrics)
                    .environmentObject(environment.settings)
                    .frame(width: showcaseCanvas.width, height: showcaseCanvas.height)
            )
        )
    }

    static func showcaseColumns() -> SnapshotScene {
        showcase("20-showcase-columns", layout: "columns")
    }

    static func showcaseCentered() -> SnapshotScene {
        showcase("21-showcase-centered", layout: "centered")
    }

    static func expandedActivities() -> SnapshotScene {
        scene("05-expanded-activities", size: expandedCanvas) { environment in
            environment.media.inject(nowPlaying())
            environment.activities.upsert(mediaActivity())
            for activity in sideActivities() {
                environment.activities.upsert(activity)
            }
            environment.viewModel.state = .expanded
        }
    }
}
