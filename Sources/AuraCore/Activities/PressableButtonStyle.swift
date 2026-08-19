import SwiftUI

/// Кнопка отзывается на нажатие: слегка проседает и возвращается с пружиной.
/// Без этого управление плеером выглядит мёртвым — визуально ничего не
/// происходит между кликом и реакцией приложения.
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.86
    var hoverScale: CGFloat = 1.06

    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : (hovering ? hoverScale : 1))
            .brightness(configuration.isPressed ? -0.06 : (hovering ? 0.08 : 0))
            .animation(
                configuration.isPressed ? .easeOut(duration: 0.1) : AuraAnimation.touch,
                value: configuration.isPressed
            )
            .animation(AuraAnimation.touch, value: hovering)
            .onHover { hovering = $0 }
    }
}
