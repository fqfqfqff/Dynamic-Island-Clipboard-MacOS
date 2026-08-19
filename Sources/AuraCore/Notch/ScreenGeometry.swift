import AppKit

/// Где на экране находится вырез и какого он размера.
struct NotchGeometry: Equatable {
    /// Прямоугольник выреза в глобальных координатах Cocoa (origin снизу слева).
    let notchRect: CGRect
    /// Высота полосы строки меню на этом экране.
    let menuBarHeight: CGFloat
    /// false — вырез виртуальный, машина или монитор без физического выреза.
    let isPhysical: Bool
    let screenFrame: CGRect

    var notchSize: CGSize { notchRect.size }
}

enum ScreenGeometry {
    /// Размер выреза, который мы рисуем сами, если физического нет.
    /// Близок к пропорциям настоящего, чтобы UI выглядел одинаково везде.
    static let virtualNotchSize = CGSize(width: 190, height: 32)

    /// Экран с физическим вырезом, иначе главный.
    /// Запасная геометрия на случай, когда экранов нет ни одного.
    static func fallbackGeometry() -> NotchGeometry {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = virtualNotchSize
        return NotchGeometry(
            notchRect: CGRect(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height,
                width: size.width,
                height: size.height
            ),
            menuBarHeight: size.height,
            isPhysical: false,
            screenFrame: frame
        )
    }

    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    @MainActor
    static func geometry(for screen: NSScreen, settings: SettingsStore) -> NotchGeometry {
        let frame = screen.frame
        let menuBarHeight = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)

        // auxiliaryTopLeftArea / auxiliaryTopRightArea — области слева и справа
        // от камеры. Берём только их ширины: так результат не зависит от того,
        // в какой системе координат система вернула сами прямоугольники.
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchWidth = frame.width - left.width - right.width
            if notchWidth > 1 {
                let rect = CGRect(
                    x: frame.minX + left.width,
                    y: frame.maxY - menuBarHeight,
                    width: notchWidth,
                    height: menuBarHeight
                )
                return NotchGeometry(
                    notchRect: rect,
                    menuBarHeight: menuBarHeight,
                    isPhysical: true,
                    screenFrame: frame
                )
            }
        }

        let size = CGSize(width: settings.virtualNotchWidth, height: virtualNotchSize.height)
        let rect = CGRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return NotchGeometry(
            notchRect: rect,
            menuBarHeight: menuBarHeight,
            isPhysical: false,
            screenFrame: frame
        )
    }
}
