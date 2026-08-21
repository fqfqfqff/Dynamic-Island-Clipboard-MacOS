import AppKit

/// Обложка приложения, нарисованная кодом.
///
/// Иконка — это то же, что делает Aura, только неподвижно: вырез сверху и
/// свет, который из него льётся. Ни буквы «A», ни абстрактной фигуры —
/// на шестнадцати точках в Dock узнаётся именно силуэт выреза.
///
/// Рисуется, а не лежит картинкой, по той же причине, что и снимки
/// интерфейса: правку видно в коде, а не в бинарном файле.
@MainActor
public enum AppIconRenderer {

    /// Полный набор размеров для `.iconset`.
    public static let sizes: [(name: String, points: Int, scale: Int)] = [
        ("icon_16x16", 16, 1), ("icon_16x16@2x", 16, 2),
        ("icon_32x32", 32, 1), ("icon_32x32@2x", 32, 2),
        ("icon_128x128", 128, 1), ("icon_128x128@2x", 128, 2),
        ("icon_256x256", 256, 1), ("icon_256x256@2x", 256, 2),
        ("icon_512x512", 512, 1), ("icon_512x512@2x", 512, 2),
    ]

    /// Пишет `.iconset` целиком и возвращает путь к каталогу.
    @discardableResult
    public static func writeIconset(to directory: URL) -> URL? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for entry in sizes {
            let pixels = entry.points * entry.scale
            guard let data = png(pixels: pixels) else { return nil }
            let url = directory.appendingPathComponent("\(entry.name).png")
            try? data.write(to: url)
        }
        return directory
    }

    public static func png(pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(side: CGFloat(pixels))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Рисование

    private static func draw(side: CGFloat) {
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        NSColor.clear.setFill()
        canvas.fill()

        // Плитка приложения занимает не весь квадрат: у иконок macOS
        // есть собственные поля, и без них она выглядит крупнее соседних.
        let inset = side * 0.09
        let plate = canvas.insetBy(dx: inset, dy: inset)
        let corner = plate.width * 0.225
        let shape = NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner)

        NSGraphicsContext.current?.saveGraphicsState()
        shape.addClip()

        // Тёмная подложка: почти чёрная, чуть теплее к низу.
        NSGradient(colors: [
            NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1),
            NSColor(srgbRed: 0.02, green: 0.02, blue: 0.04, alpha: 1),
        ])?.draw(in: plate, angle: -90)

        aurora(in: plate)
        notch(in: plate)

        NSGraphicsContext.current?.restoreGraphicsState()

        // Тонкая светлая кромка по краю плитки — та же, что у системных иконок.
        NSColor(white: 1, alpha: 0.10).setStroke()
        shape.lineWidth = max(1, side * 0.004)
        shape.stroke()
    }

    /// Свет, льющийся из выреза. Ради него всё и затевалось.
    ///
    /// Источник у света один и он привязан к вырезу: пятна расходятся
    /// из точки прямо под ним. Разбросанные по плитке, они читались просто
    /// как цветная муть, а вырез переставал быть их причиной.
    private static func aurora(in plate: CGRect) {
        let origin = CGPoint(x: plate.midX, y: plate.maxY - plate.height * 0.30)

        let blobs: [(NSColor, CGPoint, CGFloat)] = [
            // Ядро под самым вырезом — самое яркое место иконки.
            (NSColor(srgbRed: 1.00, green: 0.30, blue: 0.55, alpha: 0.70),
             CGPoint(x: origin.x, y: origin.y - plate.height * 0.02),
             plate.width * 0.30),
            (NSColor(srgbRed: 0.98, green: 0.16, blue: 0.40, alpha: 0.55),
             CGPoint(x: origin.x - plate.width * 0.17, y: origin.y - plate.height * 0.10),
             plate.width * 0.34),
            (NSColor(srgbRed: 0.52, green: 0.26, blue: 1.00, alpha: 0.60),
             CGPoint(x: origin.x + plate.width * 0.17, y: origin.y - plate.height * 0.12),
             plate.width * 0.36),
            (NSColor(srgbRed: 0.12, green: 0.80, blue: 0.98, alpha: 0.45),
             CGPoint(x: origin.x + plate.width * 0.03, y: origin.y - plate.height * 0.30),
             plate.width * 0.32),
        ]

        // Свет складывается, а не перекрывает. При обычном наложении
        // полупрозрачные пятна на почти чёрном фоне глушат друг друга,
        // и вместо свечения получается бурая муть.
        let context = NSGraphicsContext.current
        let previous = context?.compositingOperation
        context?.compositingOperation = .plusLighter

        for (color, center, radius) in blobs {
            NSGradient(
                colors: [color, color.withAlphaComponent(0)],
                atLocations: [0, 1],
                colorSpace: .sRGB
            )?.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
        }

        // Узкая яркая полоса вплотную к вырезу: без неё непонятно, что свет
        // именно из него льётся, а не просто лежит на плитке.
        let leak = CGRect(
            x: plate.midX - plate.width * 0.32,
            y: plate.maxY - plate.height * 0.27,
            width: plate.width * 0.64,
            height: plate.height * 0.06
        )
        NSGradient(
            colors: [NSColor(white: 1, alpha: 0.55), NSColor(white: 1, alpha: 0)],
            atLocations: [0, 1],
            colorSpace: .sRGB
        )?.draw(in: leak, angle: -90)

        context?.compositingOperation = previous ?? .sourceOver

        // Низ плитки уходит в темноту: свет должен кончаться, иначе он
        // растекается по всей иконке и вырез перестаёт быть его причиной.
        NSGradient(
            colors: [NSColor(white: 0, alpha: 0), NSColor(white: 0, alpha: 0.75)],
            atLocations: [0.35, 1],
            colorSpace: .sRGB
        )?.draw(in: plate, angle: -90)
    }

    /// Сам вырез: чёрная фигура, приросшая к верхней кромке.
    private static func notch(in plate: CGRect) {
        let width = plate.width * 0.60
        let height = plate.height * 0.25
        let rect = CGRect(
            x: plate.midX - width / 2,
            y: plate.maxY - height,
            width: width,
            height: height
        )

        // Скруглены только нижние углы — верх упирается в кромку экрана,
        // ровно как настоящий вырез.
        let radius = height * 0.52
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.line(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.curve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            controlPoint1: CGPoint(x: rect.minX, y: rect.minY),
            controlPoint2: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.line(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.curve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            controlPoint1: CGPoint(x: rect.maxX, y: rect.minY),
            controlPoint2: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.close()

        NSColor.black.setFill()
        path.fill()

        // Полоски звука внутри выреза — единственная деталь, которая
        // остаётся различимой и на маленьком размере.
        let barWidth = rect.width * 0.045
        let spacing = barWidth * 0.85
        let heights: [CGFloat] = [0.30, 0.62, 0.44, 0.78, 0.36]
        let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * spacing
        var x = rect.midX - total / 2

        for factor in heights {
            let barHeight = rect.height * 0.52 * factor
            let bar = CGRect(
                x: x,
                y: rect.minY + (rect.height * 0.44 - barHeight) / 2 + rect.height * 0.10,
                width: barWidth,
                height: barHeight
            )
            NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92).setFill()
            NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            x += barWidth + spacing
        }
    }
}
