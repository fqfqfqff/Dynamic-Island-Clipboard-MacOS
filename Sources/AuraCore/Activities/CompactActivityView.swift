import SwiftUI

/// Компактный вид: иконка слева от выреза, индикатор справа — ровно как на
/// iPhone, только «остров» здесь физический.
struct CompactActivityView: View {
    let activity: Activity
    let extraCount: Int
    let notchWidth: CGFloat
    let slotWidth: CGFloat

    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: slotWidth)

            Spacer(minLength: notchWidth)

            trailing
                .frame(width: slotWidth)
        }
    }

    @ViewBuilder
    private var leading: some View {
        if let artwork = activity.artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: activity.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(activity.tint)
                .symbolRenderingMode(.hierarchical)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch settings.trailingSlotStyle {
        case "none":
            EmptyView()
        case "progress":
            if case .progress(let value) = activity.indicator {
                ProgressRing(progress: value, tint: activity.tint).frame(width: 16, height: 16)
            } else {
                defaultTrailing
            }
        case "text":
            if case .text(let text) = activity.indicator {
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(activity.tint)
                    .monospacedDigit()
            } else {
                defaultTrailing
            }
        default:
            defaultTrailing
        }
    }

    @ViewBuilder
    private var defaultTrailing: some View {
        switch activity.indicator {
        case .none:
            if extraCount > 0 { extraBadge }
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
        }
    }

    private var extraBadge: some View {
        Text("+\(extraCount)")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
    }
}

struct ProgressRing: View {
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.22), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.3), value: progress)
    }
}

/// Полоски эквалайзера в свёрнутом вырезе.
///
/// Кадры задаёт `TimelineView`: обычная анимация SwiftUI перерисовывала бы
/// вырез шестьдесят раз в секунду без перерыва, а здесь частота фиксированная.
///
/// Высота полосок складывается из нескольких волн с несоизмеримыми периодами —
/// рисунок не повторяется и не выглядит машинным, — и масштабируется по
/// системной громкости: тихий звук даёт низкие полоски.
struct AudioBars: View {
    let tint: Color
    var barCount: Int = 5

    @EnvironmentObject private var spectrum: AudioSpectrumMonitor

    private let barWidth: CGFloat = 2.5
    private let spacing: CGFloat = 2

    var body: some View {
        TimelineView(.periodic(from: .now, by: spectrum.isRunning ? 0.1 : 0.18)) { context in
            // Canvas вместо стопки фигур: SwiftUI не пересобирает дерево на
            // каждом кадре, а просто перерисовывает — на профиле это была
            // основная нагрузка приложения в покое.
            let heights = frameHeights(at: context.date)

            Canvas { ctx, size in
                for index in 0..<barCount {
                    let height = heights[index]
                    let x = CGFloat(index) * (barWidth + spacing)
                    let rect = CGRect(
                        x: x,
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(tint))
                }
            }
            .frame(
                width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing,
                height: 18
            )

        }
    }

    /// Высоты текущего кадра.
    ///
    /// Никакого состояния: сглаживание живёт в мониторе спектра. Попытка
    /// хранить промежуточные высоты во `@State` и обновлять их прямо во время
    /// отрисовки приводила к бесконечной перерисовке и полной загрузке ядра.
    private func frameHeights(at date: Date) -> [CGFloat] {
        let time = date.timeIntervalSinceReferenceDate
        let loudness = CGFloat(max(0.25, min(1, SystemVolume.current)))

        return (0..<barCount).map { index in
            if spectrum.isRunning {
                let levels = spectrum.levels
                guard !levels.isEmpty else { return 3 }
                return 3 + levels[index % levels.count] * 15
            }
            return height(index: index, time: time, loudness: loudness)
        }
    }

    /// Запасной вариант, когда доступа к звуку нет.
    /// Две волны разной частоты: рисунок не повторяется и не выглядит машинным.
    /// Амплитуда масштабируется системной громкостью — тихий звук даёт низкие
    /// полоски.
    private func height(index: Int, time: TimeInterval, loudness: CGFloat) -> CGFloat {
        let phases: [Double] = [2.7, 3.9, 3.1, 4.6, 2.3]
        let offsets: [Double] = [0, 1.7, 0.6, 2.4, 1.1]
        let speed = phases[index % phases.count]
        let offset = offsets[index % offsets.count]

        let wave = sin(time * speed + offset) * 0.65 + sin(time * speed * 1.9 + offset) * 0.35
        return 3 + CGFloat((wave + 1) / 2) * 13 * loudness
    }
}

/// Точка «идёт работа». Раньше она пульсировала бесконечно — а бесконечная
/// анимация означает перерисовку выреза 60 раз в секунду, всегда.
struct PulsingDot: View {
    let tint: Color

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 8, height: 8)
            .opacity(0.85)
    }
}
