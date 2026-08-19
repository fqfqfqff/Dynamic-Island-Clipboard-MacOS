import SwiftUI

/// Единый набор анимаций острова.
///
/// Правил всего два, и оба выстраданы:
///
/// 1. Форму анимирует только модель, через `withAnimation`. Раньше поверх
///    этого висел ещё и модификатор `.animation` на размере — две системы
///    пересчитывали одно и то же движение с разными кривыми, и на их стыке
///    появлялся рывок.
/// 2. Содержимое не едет вместе с формой. Оно появляется чуть позже, когда
///    панель уже почти раскрылась, и исчезает раньше, чем она начнёт
///    сворачиваться, — иначе на экране два несогласованных движения.
enum AuraAnimation {
    /// Раскрытие и ширина боковых слотов.
    ///
    /// Демпфирование высокое: отскок на панели такого размера выглядит
    /// дёшево, а на маленькой пилюле его всё равно не видно.
    static let notch: Animation = .spring(response: 0.48, dampingFraction: 0.84)

    /// Сворачивание — заметно медленнее раскрытия.
    ///
    /// Симметричные длительности выглядят неряшливо: раскрытие пользователь
    /// вызывает сам и ждёт отклика, а сворачивание происходит «вслед» и должно
    /// успокаиваться, а не схлопываться.
    static let notchCollapse: Animation = .spring(response: 0.6, dampingFraction: 0.9)

    /// Появление содержимого — с задержкой, чтобы дождаться формы.
    static let contentIn: Animation = .easeOut(duration: 0.24).delay(0.1)

    /// Исчезновение содержимого: успевает уйти до того, как схлопнется форма,
    /// но не мигает.
    static let contentOut: Animation = .easeInOut(duration: 0.28)

    /// Смена содержимого на месте: обложка, название трека.
    static let content: Animation = .easeInOut(duration: 0.28)

    /// Мелкие отклики: наведение, нажатие.
    static let touch: Animation = .spring(response: 0.25, dampingFraction: 0.72)
}

extension AnyTransition {
    /// Переход для содержимого раскрытой панели.
    static var auraContent: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.95, anchor: .top))
                .animation(AuraAnimation.contentIn),
            removal: .opacity.animation(AuraAnimation.contentOut)
        )
    }

    /// Переход для компактных значков по краям выреза.
    static var auraCompact: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.7))
                .animation(AuraAnimation.notch),
            removal: .opacity.animation(AuraAnimation.contentOut)
        )
    }
}
