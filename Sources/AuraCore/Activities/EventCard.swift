import SwiftUI

/// Карточка уведомления: вырез вырастает сверху вниз ровно на одну строку.
///
/// Это не панель и не список — здесь помещается только то, ради чего человек
/// поднимает глаза: чьё приложение, от кого сообщение и что именно пришло.
/// Всё остальное — в раскрытой панели, до которой достаточно довести курсор.
struct EventCard: View {
    let message: NotificationMirrorProvider.Message
    /// Сколько всего непрочитанного от этого приложения.
    var unread: Int = 1
    /// nil — отвечать некуда: баннер уже исчез.
    var onReply: (() -> Void)?
    /// Вставить код подтверждения в то приложение, где сейчас курсор.
    var onPasteCode: ((String) -> Void)?

    @EnvironmentObject private var settings: SettingsStore

    private var design: Font.Design { AuraTheme.design(settings.fontDesign) }

    /// Насколько крупнее обычного. Уведомление читают боковым зрением
    /// и мельком — размер здесь важнее плотности.
    private var scale: CGFloat { CGFloat(settings.notificationScale) }

    var body: some View {
        HStack(spacing: 11 * scale) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text(message.sender)
                    .font(.system(size: 13 * scale, weight: .semibold, design: design))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(secondLine)
                    .font(.system(size: 11 * scale, weight: .regular, design: design))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // Код подтверждения — самое частое, ради чего вообще смотрят
            // на такое уведомление. macOS подставляет коды сама, но только
            // в поля, которые сама и распознала: в терминале или в чужом
            // приложении их набирают руками.
            if let code = message.code, let onPasteCode {
                Button { onPasteCode(code) } label: {
                    Text(code)
                        .font(.system(size: 13 * scale, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 9 * scale)
                        .padding(.vertical, 4 * scale)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(PressableButtonStyle())
                .help(t("ui.2b6f40e1", "Вставить код"))
            }

            if let onReply {
                Button(action: onReply) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 26 * scale, height: 26 * scale)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(PressableButtonStyle())
                .help(t("ui.8c0b41a6", "Ответить"))
            }

            counter
        }
        .padding(.horizontal, 15 * scale)
    }

    /// Вторая строка: что пришло, и сколько ещё ждёт.
    ///
    /// Пачка сообщений подряд — это одна карточка, а не пять по очереди:
    /// показывать нужно последнее, но так, чтобы было видно, что оно
    /// не единственное.
    private var secondLine: String {
        message.body ?? message.kind.wording
    }

    /// Иконка самого приложения: по ней сразу видно, куда идти отвечать.
    /// Значок типа сообщения при этом никуда не делся — он висит уголком.
    private var icon: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = message.icon {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                        .fill(.white.opacity(0.12))
                        .overlay {
                            Image(systemName: message.kind.symbol)
                                .font(.system(size: 14 * scale, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 32 * scale, height: 32 * scale)

            // Уголок с типом: для текста его не показываем — облачко рядом
            // с иконкой мессенджера ничего не добавляет.
            if message.kind != .text {
                Image(systemName: message.kind.symbol)
                    .font(.system(size: 9 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3 * scale)
                    .background(Circle().fill(.black.opacity(0.75)))
                    .offset(x: 4, y: 3)
            }
        }
    }

    /// Сколько непрочитанного ждёт в этом разговоре.
    ///
    /// Единица не показывается: одно сообщение — это и так одно сообщение,
    /// а лишняя цифра рядом с текстом только отвлекает.
    @ViewBuilder
    private var counter: some View {
        if unread > 1 {
            Text("\(unread)")
                .font(.system(size: 14 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }
}

/// Обводка карточки в цвет приложения.
///
/// Цвет берётся с иконки — у Telegram он голубой, у почты синий, — и это
/// единственное, что отличает одно уведомление от другого боковым зрением.
struct EventRim: View {
    let shape: NotchShape
    let tint: Color

    var body: some View {
        ZStack {
            shape
                .stroke(
                    LinearGradient(
                        colors: [tint.opacity(0.9), tint.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
            // Мягкое свечение наружу: обводка в один пиксель на чёрном фоне
            // теряется, а с ним карточка читается как подсвеченная.
            shape
                .stroke(tint.opacity(0.5), lineWidth: 2.5)
                .blur(radius: 6)
        }
        .allowsHitTesting(false)
    }
}
