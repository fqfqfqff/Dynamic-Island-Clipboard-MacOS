import SwiftUI

/// Текст, который не влезает, медленно проезжает туда и обратно.
///
/// Обрезать название трека многоточием — потеря: у половины треков самое
/// важное как раз в конце. Прокрутка включается только когда текст
/// действительно шире места, и живёт лишь пока панель раскрыта.
struct MarqueeText: View {
    let text: String
    var font: Font
    var color: Color

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }
    private var needsScrolling: Bool { overflow > 4 }

    var body: some View {
        GeometryReader { geometry in
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
                .offset(x: offset)
                .frame(width: geometry.size.width, alignment: .leading)
                .clipped()
                .onAppear {
                    containerWidth = geometry.size.width
                    startIfNeeded()
                }
                .onChange(of: text) { _, _ in
                    // Новый трек — начинаем с начала строки.
                    offset = 0
                    startIfNeeded()
                }
        }
    }

    private func startIfNeeded() {
        guard needsScrolling else {
            offset = 0
            return
        }

        // Скорость постоянная, а не длительность: длинное название иначе
        // проезжало бы быстрее короткого.
        let duration = Double(overflow) / 22

        withAnimation(
            .easeInOut(duration: duration)
            .delay(1.4)
            .repeatForever(autoreverses: true)
        ) {
            offset = -overflow
        }
    }
}
