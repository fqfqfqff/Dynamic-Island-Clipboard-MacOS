import SwiftUI

/// Текст, который не влезает, едет по кругу.
///
/// Обрезать название трека многоточием — потеря: у половины треков самое
/// важное как раз в конце, а у исполнителей — второе имя в дуэте.
///
/// Едет именно по кругу, а не туда-обратно: строка уезжает влево и следом
/// за ней въезжает её же копия. Маятник читается как дёрганье — глаз ловит
/// момент разворота, и приходится ждать, пока строка вернётся.
struct MarqueeText: View {
    let text: String
    var font: Font
    var color: Color
    /// Точек в секунду. Скорость постоянная, а не длительность: иначе
    /// длинное название проезжало бы быстрее короткого.
    var speed: CGFloat = 24
    /// Зазор между концом строки и её повтором.
    var gap: CGFloat = 38

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var needsScrolling: Bool { textWidth > containerWidth + 2 }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if needsScrolling {
                    HStack(spacing: gap) {
                        label
                        // Вторая копия и делает движение круговым: пока
                        // первая уезжает, эта уже въезжает справа.
                        label
                    }
                    .offset(x: offset)
                    .frame(width: geometry.size.width, alignment: .leading)
                } else {
                    label.frame(width: geometry.size.width, alignment: .center)
                }
            }
            .clipped()
            // Мягкие кромки: строка, обрезанная по живому, читается как
            // ошибка вёрстки, а не как движение.
            .mask(needsScrolling ? AnyView(edgeFade) : AnyView(Color.black))
            .onAppear {
                containerWidth = geometry.size.width
                restart()
            }
            .onChange(of: geometry.size.width) { _, width in
                containerWidth = width
                restart()
            }
            .onChange(of: text) { _, _ in restart() }
            .onChange(of: textWidth) { _, _ in restart() }
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .background {
                GeometryReader { textGeometry in
                    Color.clear.onAppear { textWidth = textGeometry.size.width }
                }
            }
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.045),
                .init(color: .black, location: 0.955),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func restart() {
        // Прерываем текущее движение: без этого повторная анимация ложится
        // поверх старой и строка начинает дёргаться.
        withAnimation(.linear(duration: 0)) { offset = 0 }

        guard needsScrolling else { return }
        let distance = textWidth + gap

        withAnimation(
            .linear(duration: Double(distance / speed))
            .delay(1.2)
            .repeatForever(autoreverses: false)
        ) {
            offset = -distance
        }
    }
}
