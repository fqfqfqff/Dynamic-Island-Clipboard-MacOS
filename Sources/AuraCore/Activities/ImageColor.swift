import AppKit
import SwiftUI

/// Один контекст на всё приложение: его создание стоит десятки миллисекунд,
/// а именно из-за этого подстройка цвета под обложку заметно запаздывала.
private let sharedCIContext = CIContext(options: [.workingColorSpace: NSNull()])

extension NSImage {
    /// Заранее размытая копия для подложки.
    ///
    /// Раньше размытие висело модификатором `.blur` прямо на анимируемом виде,
    /// и SwiftUI пересчитывал его на каждом кадре раскрытия — отсюда рывки.
    /// Здесь оно считается один раз на трек.
    func blurred(radius: Double) -> NSImage? {
        guard radius > 0,
              let tiff = tiffRepresentation,
              let input = CIImage(data: tiff) else { return nil }

        guard let filter = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: input.clampedToExtent(),
            kCIInputRadiusKey: radius,
        ]), let output = filter.outputImage?.cropped(to: input.extent) else { return nil }

        guard let cgImage = sharedCIContext.createCGImage(output, from: input.extent)
        else { return nil }

        return NSImage(cgImage: cgImage, size: size)
    }

    /// Средний цвет обложки — им подкрашивается карточка плеера.
    ///
    /// Считается по картинке, сжатой до одного пикселя: это делает GPU за
    /// один проход, перебирать пиксели вручную незачем.
    var averageColor: NSColor? {
        guard let tiff = tiffRepresentation,
              let source = CIImage(data: tiff) else { return nil }

        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: source,
            kCIInputExtentKey: CIVector(cgRect: extent),
        ])
        guard let output = filter?.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        sharedCIContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }

    /// Тот же цвет, но пригодный для подложки: приглушённый и не слишком тёмный,
    /// иначе карточка сливается с чёрным вырезом.
    var accentColor: Color {
        guard let average = averageColor?.usingColorSpace(.sRGB) else { return .pink }

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return Color(
            nsColor: NSColor(
                hue: hue,
                saturation: min(1, max(0.35, saturation * 1.3)),
                brightness: min(1, max(0.55, brightness * 1.4)),
                alpha: 1
            )
        )
    }
}
