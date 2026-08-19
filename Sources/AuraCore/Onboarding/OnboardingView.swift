import SwiftUI

/// Экран первого запуска: проводит через разрешения и объясняет, зачем каждое.
///
/// Без него человек остаётся один на один с четырьмя системными запросами,
/// о которых нигде не сказано, — и обычно просто удаляет приложение.
struct OnboardingView: View {
    let onFinish: () -> Void

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var media: NowPlayingProvider
    @EnvironmentObject private var spectrum: AudioSpectrumMonitor

    @State private var refreshToken = 0
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(items, id: \.title) { item in
                        row(item)
                    }
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 560, height: 560)
        .onReceive(refresh) { _ in refreshToken += 1 }
    }

    // MARK: - Шапка и подвал

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tint)
            Text("Aura")
                .font(.system(size: 22, weight: .bold))
            Text("Вырез MacBook становится плеером, а буфер обмена — историей.\nОсталось выдать несколько разрешений: без них часть функций просто не сможет работать.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 22)
    }

    private var footer: some View {
        HStack {
            Text("Разрешения можно выдать и позже — в настройках.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Готово", action: onFinish)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: - Строки

    private struct Item {
        let title: String
        let purpose: String
        let symbol: String
        let state: PermissionStatus.State
        let action: () -> Void
        let optional: Bool
    }

    private var items: [Item] {
        _ = refreshToken   // пересобираем список, когда таймер тикнул

        return [
            Item(
                title: "Универсальный доступ",
                purpose: "Вставка из буфера по ⌥⌘V и зеркало уведомлений.",
                symbol: "hand.raised.fill",
                state: PermissionStatus.accessibility,
                action: {
                    Permissions.requestAccessibility()
                    PermissionStatus.open(.accessibility)
                },
                optional: false
            ),
            Item(
                title: "Управление плеерами",
                purpose: "Трек, обложка и перемотка в Музыке и Spotify. Без этого остаётся только название приложения.",
                symbol: "music.note",
                state: PermissionStatus.automation(settings: settings, media: media),
                action: {
                    settings.musicAccessBlocked = false
                    media.retryAccess()
                    PermissionStatus.open(.automation)
                },
                optional: false
            ),
            Item(
                title: "Запись звука",
                purpose: "Полоски эквалайзера двигаются по реальным частотам. Ничего не записывается — считаются только уровни.",
                symbol: "waveform",
                state: PermissionStatus.audio(spectrum: spectrum, settings: settings),
                action: {
                    settings.reactToAudio = true
                    PermissionStatus.open(.audio)
                },
                optional: true
            ),
            Item(
                title: "Bluetooth",
                purpose: "Заряд наушников при подключении.",
                symbol: "airpods",
                state: PermissionStatus.bluetooth,
                action: { PermissionStatus.open(.bluetooth) },
                optional: true
            ),
            Item(
                title: "Полный доступ к диску",
                purpose: "Только ради режима фокусирования: состояние «Не беспокоить» лежит в защищённом файле.",
                symbol: "moon.fill",
                state: PermissionStatus.fullDisk,
                action: { PermissionStatus.open(.fullDisk) },
                optional: true
            ),
            Item(
                title: "Заставка",
                purpose: "Плеер на заблокированном экране. Установлена скриптом — осталось выбрать её в настройках системы.",
                symbol: "lock.display",
                state: PermissionStatus.screensaverInstalled ? .granted : .unknown,
                action: { PermissionStatus.open(.screensaver) },
                optional: true
            ),
        ]
    }

    private func row(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.symbol)
                .font(.system(size: 17))
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                    if item.optional {
                        Text("необязательно")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                    }
                }
                Text(item.purpose)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            status(item)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.3)))
    }

    @ViewBuilder
    private func status(_ item: Item) -> some View {
        switch item.state {
        case .granted:
            Label("выдано", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .denied, .unknown:
            Button(item.state == .denied ? "Выдать" : "Проверить", action: item.action)
                .font(.system(size: 11))
        }
    }
}
