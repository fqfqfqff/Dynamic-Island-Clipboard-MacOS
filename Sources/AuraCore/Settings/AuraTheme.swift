import SwiftUI

/// Оформление, собранное из настроек: фон, стекло, акцент, шрифт.
/// Вынесено отдельно, чтобы остров, плеер и витрина одинаково понимали
/// один и тот же выбор пользователя.
enum AuraTheme {
    // MARK: - Градиенты

    struct GradientPreset: Identifiable {
        let id: String
        let name: String
        let colors: [Color]
    }

    static let gradients: [GradientPreset] = [
        .init(id: "midnight", name: "Полночь", colors: [
            Color(red: 0.05, green: 0.06, blue: 0.15),
            Color(red: 0.16, green: 0.09, blue: 0.28),
        ]),
        .init(id: "sunset", name: "Закат", colors: [
            Color(red: 0.35, green: 0.10, blue: 0.20),
            Color(red: 0.55, green: 0.25, blue: 0.10),
        ]),
        .init(id: "ocean", name: "Океан", colors: [
            Color(red: 0.03, green: 0.16, blue: 0.26),
            Color(red: 0.05, green: 0.32, blue: 0.36),
        ]),
        .init(id: "forest", name: "Хвоя", colors: [
            Color(red: 0.05, green: 0.16, blue: 0.11),
            Color(red: 0.11, green: 0.26, blue: 0.18),
        ]),
        .init(id: "graphite", name: "Графит", colors: [
            Color(red: 0.09, green: 0.09, blue: 0.10),
            Color(red: 0.20, green: 0.20, blue: 0.22),
        ]),
        .init(id: "berry", name: "Ягода", colors: [
            Color(red: 0.24, green: 0.05, blue: 0.22),
            Color(red: 0.44, green: 0.10, blue: 0.30),
        ]),
    ]

    static func gradient(_ id: String) -> LinearGradient {
        let preset = gradients.first { $0.id == id } ?? gradients[0]
        return LinearGradient(
            colors: preset.colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Акцент

    /// Цвет, которым красятся полоса прогресса, кнопка воспроизведения
    /// и полоски частот.
    @MainActor
    static func accent(for artworkAccent: Color, settings: SettingsStore) -> Color {
        guard settings.accentSource == "fixed" else { return artworkAccent }
        return color(fromHex: settings.accentHex) ?? artworkAccent
    }

    static func color(fromHex hex: String) -> Color? {
        var value = hex.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("#") else { return nil }
        value.removeFirst()
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }

        return Color(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }

    // MARK: - Шрифт


    static func design(_ id: String) -> Font.Design {
        switch id {
        case "rounded": .rounded
        case "serif": .serif
        default: .default
        }
    }
}

extension Color {
    /// Шестнадцатеричная запись — в таком виде цвет уходит в настройки.
    var hexString: String {
        let native = NSColor(self).usingColorSpace(.sRGB) ?? .systemPink
        return String(
            format: "#%02X%02X%02X",
            Int(round(native.redComponent * 255)),
            Int(round(native.greenComponent * 255)),
            Int(round(native.blueComponent * 255))
        )
    }
}
