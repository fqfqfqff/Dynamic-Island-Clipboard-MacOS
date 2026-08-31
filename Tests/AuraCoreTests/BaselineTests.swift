import AppKit
import XCTest
@testable import AuraCore

/// Сравнение с эталонами.
///
/// Половина правок в этом проекте — визуальные, и до сих пор каждая
/// проверялась глазами: срезанное свечение, красная обводка вместо белой,
/// значок не на месте. Эталоны ловят такое сами.
///
/// Сцены берутся только те, что не зависят от времени: у плеера бежит
/// полоса, у витрины идут часы — их пиксели меняются каждую секунду,
/// и эталон для них был бы вечно красным.
@MainActor
final class BaselineTests: XCTestCase {
    /// Какой доле точек позволено разойтись с эталоном.
    ///
    /// Считаем именно долю разошедшихся точек, а не среднюю разницу
    /// по кадру: средняя размазывает мелкие правки в ноль. Сдвиг пилюли
    /// счётчика меняет тысячные доли кадра — и в среднем не виден вовсе,
    /// хотя это ровно то, что тест должен ловить.
    private let tolerance = 0.004
    /// Насколько точка должна отличаться, чтобы считаться другой.
    /// Сглаживание шрифтов даёт разброс в единицы процентов.
    private let pixelThreshold = 0.06

    private static let scenes = [
        "01-collapsed-empty", "03-peek", "06-notification",
        "08-peek-hint", "09-notification-badge", "12-notification-long",
    ]

    func testScenesMatchBaselines() throws {
        _ = NSApplication.shared
        let folder = try baselineFolder()

        for scene in SnapshotScenes.all() where Self.scenes.contains(scene.name) {
            let url = folder.appendingPathComponent("\(scene.name).png")
            guard let reference = NSImage(contentsOf: url).flatMap(bitmap) else {
                throw XCTSkip("нет эталона \(scene.name) — соберите их через Scripts/baselines.sh")
            }

            guard let data = SnapshotRenderer.png(of: scene),
                  let rendered = NSBitmapImageRep(data: data) else {
                throw XCTSkip("отрисовка в этом окружении недоступна")
            }

            let difference = compare(rendered, reference)
            if difference > tolerance {
                // Кадр сохраняется рядом: глазами сравнить проще, чем
                // по числу.
                let failure = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("\(scene.name)-actual.png")
                try? data.write(to: failure)

                XCTFail("""
                    Сцена «\(scene.name)»: разошлось \
                    \(String(format: "%.2f", difference * 100))% точек.
                    Что вышло: \(failure.path)
                    Если так и задумано — обновите эталоны: Scripts/baselines.sh
                    """)
            }
        }
    }

    // MARK: - Опоры

    private func bitmap(_ image: NSImage) -> NSBitmapImageRep? {
        image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
    }

    /// Доля точек, разошедшихся с эталоном.
    private func compare(_ left: NSBitmapImageRep, _ right: NSBitmapImageRep) -> Double {
        guard left.pixelsWide == right.pixelsWide,
              left.pixelsHigh == right.pixelsHigh else { return 1 }

        var different = 0
        var count = 0
        for x in stride(from: 0, to: left.pixelsWide, by: 2) {
            for y in stride(from: 0, to: left.pixelsHigh, by: 2) {
                guard let a = left.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let b = right.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }

                let delta = max(
                    abs(Double(a.redComponent - b.redComponent)),
                    max(
                        abs(Double(a.greenComponent - b.greenComponent)),
                        abs(Double(a.blueComponent - b.blueComponent))
                    )
                )
                if delta > pixelThreshold { different += 1 }
                count += 1
            }
        }
        return count > 0 ? Double(different) / Double(count) : 1
    }

    private func baselineFolder() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1, url.lastPathComponent != "Tests" {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent("Baselines")
    }
}
