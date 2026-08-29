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
    /// Открыть приложение, которое прислало уведомление. В отличие от
    /// ответа, доступно всегда.
    var onOpen: (() -> Void)?
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

            // Зазор до счётчика: с многоточием текст иначе притирается
            // к цифре вплотную и читается как одно слово.
            Spacer(minLength: 14 * scale)

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

            if onReply == nil, let onOpen {
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 11 * scale, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 26 * scale, height: 26 * scale)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(PressableButtonStyle())
                .help(t("ui.f2081c34", "Открыть приложение"))
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
            UnreadPill(text: "\(unread)", tint: .white, scale: scale)
        }
    }
}

/// Обводка карточки в цвет приложения.
///
/// Цвет берётся с иконки — у Telegram он голубой, у почты синий, — и это
/// единственное, что отличает одно уведомление от другого боковым зрением.
/// Поэтому она должна быть заметна: тонкая линия в один пиксель на чёрном
/// теряется, особенно если цвет приложения тёмный.
///
/// Свет по ней бежит по кругу — так карточка читается как живая, а не
/// как нарисованная рамка. Живёт это ровно столько, сколько висит само
/// уведомление: несколько секунд.
struct EventRim: View {
    let shape: NotchShape
    let tint: Color

    @EnvironmentObject private var settings: SettingsStore

    /// Вспышка в первый момент: карточка приходит ярче, чем живёт потом.
    @State private var settled = false
    /// Момент появления — от него и считается ход блика.
    @State private var appearedAt = Date()

    /// Сколько блик идёт по кругу.
    private var period: Double { 3.4 * max(0.5, settings.animationSpeed) }

    var body: some View {
        // Ход блика считается от часов, а не анимацией состояния.
        //
        // `repeatForever` перезапускает анимацию на каждом круге, и на стыке
        // виден рывок: значение прыгает с конца в начало, а SwiftUI успевает
        // вставить между ними кадр. От часов ход непрерывен по определению —
        // круг просто продолжается.
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            content(phase: phase(at: context.date))
        }
    }

    private func phase(at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(appearedAt)
        return CGFloat((elapsed / period).truncatingRemainder(dividingBy: 1))
    }

    private func content(phase: CGFloat) -> some View {
        ZStack {
            // Тонкая линия — основа. Именно она и должна читаться как
            // обводка: широкое свечение вокруг выреза выглядело подтёком,
            // а не аккуратным контуром.
            shape
                .stroke(
                    LinearGradient(
                        colors: [vivid, vivid.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )

            // Блик бежит по самой линии — отрезком контура, а не поворотом
            // градиента. Разница видна сразу: угловой градиент крутится
            // с постоянной угловой скоростью, а карточка вытянутая — по
            // длинным сторонам свет летел, по коротким полз. Отрезок контура
            // идёт с постоянной скоростью по длине пути, как и должен.
            // Хвост — набор отрезков контура с плавным затуханием.
            //
            // Отрезки идут встык, а не внахлёст. Это важнее, чем кажется:
            // полупрозрачные штрихи в местах перекрытия складываются,
            // и там, где они находят друг на друга, получается полоса ярче
            // соседей. Ровно эти полосы и читались как ступеньки — не сама
            // кривая затухания была виновата, а сложение прозрачностей.
            //
            // Отрезков вдвое больше, шаг яркости между соседями — меньше
            // процента, а лёгкое размытие поверх стирает и швы: они длиной
            // в несколько точек, размытие в две с половиной их закрывает.
            ZStack {
                ForEach(0..<Self.tailSegments, id: \.self) { index in
                    let position = CGFloat(index) / CGFloat(Self.tailSegments - 1)
                    let step = Self.tailLength / CGFloat(Self.tailSegments - 1)

                    comet(
                        phase: phase,
                        from: position * Self.tailLength,
                        // Крошечный нахлёст — только чтобы сглаживание
                        // не оставляло между отрезками волосяного просвета.
                        to: position * Self.tailLength + step * 1.08,
                        color: Self.tailColor(at: position, tint: vivid),
                        opacity: Self.tailFade(at: position),
                        width: 1.2 + (1 - position) * 1.3
                    )
                }
            }
            .blur(radius: 2.5)

            // Голова — поверх и без размытия: размытый хвост читается как
            // свечение, но сам огонёк должен быть чётким, иначе движение
            // выглядит ватным.
            comet(
                phase: phase,
                from: 0,
                to: Self.tailLength * 0.06,
                color: .white,
                opacity: 0.9,
                width: 1.4
            )

            // Одно мягкое свечение — только чтобы линия не выглядела
            // приклеенной. Оно едва заметно и сразу за линией затухает.
            shape
                .stroke(vivid.opacity(settled ? 0.35 : 0.6), lineWidth: 2)
                .blur(radius: 5)
        }
        .allowsHitTesting(false)
        .onAppear {
            appearedAt = Date()
            withAnimation(.easeOut(duration: 0.9)) { settled = true }
        }
    }

    /// Сколько отрезков в хвосте и какой он длины по контуру.
    private static let tailSegments = 22
    private static let tailLength: CGFloat = 0.2

    /// Яркость вдоль хвоста.
    ///
    /// Не косинус и не прямая: у головы свет должен держаться почти
    /// неизменным, а к концу уходить в ноль медленно. Косинус давал
    /// заметный перелом в середине — именно он и читался как «переход
    /// от яркого к тусклому» вместо ровного затухания.
    static func tailFade(at position: CGFloat) -> Double {
        // Сглаженная ступень в кубе: у головы почти плато, к хвосту —
        //длинный пологий спуск без перелома в середине, который даёт косинус.
        let left = Double(1 - position)
        let smooth = left * left * (3 - 2 * left)
        return smooth * smooth
    }

    /// Голова белая, дальше цвет приложения — переход тоже плавный.
    ///
    /// Смешиваем руками: `Color.mix(with:by:)` появился только в macOS 15,
    /// а проект живёт с 14.4.
    static func tailColor(at position: CGFloat, tint: Color) -> Color {
        let whiteness = max(0, 1 - Double(position) / 0.22) * 0.85
        guard whiteness > 0.001,
              let base = NSColor(tint).usingColorSpace(.sRGB) else { return tint }

        func blend(_ value: CGFloat) -> Double { Double(value + (1 - value) * whiteness) }
        return Color(
            red: blend(base.redComponent),
            green: blend(base.greenComponent),
            blue: blend(base.blueComponent)
        )
    }

    /// Один отрезок хвоста: кусок контура позади головы.
    @ViewBuilder
    private func comet(
        phase: CGFloat, from: CGFloat, to: CGFloat,
        color: Color, opacity: Double, width: CGFloat
    ) -> some View {
        let tinted = color.opacity(opacity)
        // Встык, а не круглыми наконечниками: круглые дают бусины на стыках
        // соседних отрезков, а перекрытие и без них закрывает шов.
        let style = StrokeStyle(lineWidth: width, lineCap: .butt)

        // `trim` не умеет через ноль, поэтому на стыке рисуем двумя кусками.
        let start = phase - to
        let end = phase - from

        if start >= 0 {
            shape.trim(from: start, to: end).stroke(tinted, style: style)
        } else if end <= 0 {
            shape.trim(from: 1 + start, to: 1 + end).stroke(tinted, style: style)
        } else {
            shape.trim(from: 0, to: end).stroke(tinted, style: style)
            shape.trim(from: 1 + start, to: 1).stroke(tinted, style: style)
        }
    }

    /// Цвет иконки, поднятый до свечения.
    ///
    /// Акцент снимается с самой иконки, и у тёмных он выходит почти чёрным —
    /// такая обводка не видна вовсе. Тон сохраняем, яркость и насыщенность
    /// поднимаем до различимых.
    private var vivid: Color {
        guard let base = NSColor(tint).usingColorSpace(.sRGB) else { return tint }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return Color(
            hue: Double(hue),
            saturation: Double(min(1, max(saturation, 0.55))),
            brightness: Double(min(1, max(brightness, 0.9)))
        )
    }
}
