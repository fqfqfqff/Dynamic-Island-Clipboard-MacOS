import AppKit
import XCTest
@testable import AuraCore

/// Снимки интерфейса проверяются не на «красиво», а на то, что остров вообще
/// оказался там, где должен, и не разлился по всему кадру.
///
/// Ровно это и случилось при первом запуске инструмента: размытая обложка
/// внутри панели растягивалась «по заполнению», возвращала размер больше
/// предложенного — и вместо пилюли в вырезе выходил чёрный прямоугольник
/// во весь холст. На глаз в приложении это не замечалось годами.
@MainActor
final class SnapshotRendererTests: XCTestCase {

    func testCollapsedIslandStaysInTheNotch() throws {
        let scene = SnapshotScenes.collapsedMusic()
        let bitmap = try render(scene)

        let scale = CGFloat(bitmap.pixelsWide) / scene.size.width
        let middle = bitmap.pixelsWide / 2

        // В вырезе — чёрная пилюля.
        XCTAssertLessThan(
            brightness(bitmap, x: middle, y: Int(6 * scale)), 0.1,
            "остров не нарисовался в вырезе"
        )
        // Слева от выреза — обои, а не панель.
        XCTAssertGreaterThan(
            brightness(bitmap, x: Int(30 * scale), y: Int(6 * scale)), 0.1,
            "панель накрыла строку меню целиком"
        )
        // Под вырезом в свёрнутом виде не должно быть ничего.
        XCTAssertGreaterThan(
            brightness(bitmap, x: middle, y: bitmap.pixelsHigh - Int(10 * scale)), 0.1,
            "свёрнутый остров разлился вниз по холсту"
        )
    }

    func testEverySceneRenders() throws {
        for scene in SnapshotScenes.all() {
            let bitmap = try render(scene)
            XCTAssertGreaterThan(bitmap.pixelsWide, 0, "сцена \(scene.name) пустая")
        }
    }

    // MARK: - Опоры

    private func render(_ scene: SnapshotScene) throws -> NSBitmapImageRep {
        // Видам нужен инициализированный NSApplication: без него AppKit
        // не доводит слои до отрисовки.
        _ = NSApplication.shared
        guard let data = SnapshotRenderer.png(of: scene),
              let bitmap = NSBitmapImageRep(data: data) else {
            throw XCTSkip("отрисовка в этом окружении недоступна")
        }
        return bitmap
    }

    private func brightness(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        let clampedX = min(max(0, x), bitmap.pixelsWide - 1)
        let clampedY = min(max(0, y), bitmap.pixelsHigh - 1)
        guard let color = bitmap.colorAt(x: clampedX, y: clampedY)?
            .usingColorSpace(.sRGB) else { return 0 }
        return color.brightnessComponent
    }
}
