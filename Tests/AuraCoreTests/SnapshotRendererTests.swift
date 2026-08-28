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

    /// Витрина занимает весь экран, и всё, что прижато к его краям, уезжало
    /// за него: слой размытой обложки с `.aspectRatio(.fill)` возвращал
    /// размер больше предложенного, и корневой стек вырастал из 1280×800
    /// в квадрат 1280×1280. Часы оказывались на 240 точек выше видимой
    /// области, подсказка — на столько же ниже. Выглядело это не как
    /// смещение, а как «часов просто нет».
    func testShowcaseKeepsClockAndHintOnScreen() throws {
        let scene = SnapshotScenes.showcaseCentered()
        let bitmap = try render(scene)
        let scale = CGFloat(bitmap.pixelsWide) / scene.size.width

        let clock = CGRect(x: 20, y: 15, width: 220, height: 95)
        XCTAssertGreaterThan(
            brightest(bitmap, in: clock, scale: scale), 0.35,
            "часов не видно — корневой стек вырос за пределы экрана"
        )

        let hint = CGRect(
            x: scene.size.width / 2 - 260, y: scene.size.height - 56,
            width: 520, height: 42
        )
        XCTAssertGreaterThan(
            brightest(bitmap, in: hint, scale: scale), 0.12,
            "подсказки не видно — нижний край уехал за экран"
        )
    }

    /// Подсветка карточки не просто есть — по ней бежит свет. Проверяется
    /// это единственным доступным способом: два кадра в разные моменты
    /// не должны совпасть. Заодно ловится случай, когда анимация встала
    /// (`repeatForever` без `onAppear` молча ничего не делает).
    func testRimLightKeepsMoving() throws {
        // Все кадры — после того, как отыграла вспышка появления: иначе тест
        // проходил бы и с неподвижной обводкой.
        //
        // Кадров три, а не два: блик обходит круг за пару секунд, и половину
        // круга он проводит в скрытой верхней части — там, где обводка уходит
        // под кромку выреза. Два кадра могли случайно застать его в одном
        // и том же невидимом месте.
        let scene = SnapshotScenes.notificationEvent()
        let frames = try [1.3, 2.0, 2.6].map { try render(scene, settling: $0) }

        let moved = [
            biggestDifference(frames[0], frames[1]),
            biggestDifference(frames[1], frames[2]),
            biggestDifference(frames[0], frames[2]),
        ].max() ?? 0

        XCTAssertGreaterThan(
            moved, 0.05, "подсветка неподвижна — свет по обводке не бежит"
        )
    }

    func testEverySceneRenders() throws {
        for scene in SnapshotScenes.all() {
            let bitmap = try render(scene)
            XCTAssertGreaterThan(bitmap.pixelsWide, 0, "сцена \(scene.name) пустая")
        }
    }

    // MARK: - Опоры

    /// Самая изменившаяся точка двух кадров. Среднее здесь не годится:
    /// обводка занимает доли процента кадра, и любое движение по ней
    /// растворяется в чёрном фоне.
    private func biggestDifference(
        _ first: NSBitmapImageRep, _ second: NSBitmapImageRep
    ) -> CGFloat {
        var biggest: CGFloat = 0
        for x in stride(from: 0, to: min(first.pixelsWide, second.pixelsWide), by: 2) {
            for y in stride(from: 0, to: min(first.pixelsHigh, second.pixelsHigh), by: 2) {
                biggest = max(
                    biggest,
                    abs(brightness(first, x: x, y: y) - brightness(second, x: x, y: y))
                )
            }
        }
        return biggest
    }

    private func render(
        _ scene: SnapshotScene, settling: TimeInterval
    ) throws -> NSBitmapImageRep {
        var copy = scene
        copy.settleTime = settling
        return try render(copy)
    }

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

    /// Самая светлая точка в прямоугольнике, заданном в точках вида.
    private func brightest(
        _ bitmap: NSBitmapImageRep, in rect: CGRect, scale: CGFloat
    ) -> CGFloat {
        var best: CGFloat = 0
        for x in stride(from: Int(rect.minX * scale), to: Int(rect.maxX * scale), by: 2) {
            for y in stride(from: Int(rect.minY * scale), to: Int(rect.maxY * scale), by: 2) {
                best = max(best, brightness(bitmap, x: x, y: y))
            }
        }
        return best
    }

    private func brightness(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        let clampedX = min(max(0, x), bitmap.pixelsWide - 1)
        let clampedY = min(max(0, y), bitmap.pixelsHigh - 1)
        guard let color = bitmap.colorAt(x: clampedX, y: clampedY)?
            .usingColorSpace(.sRGB) else { return 0 }
        return color.brightnessComponent
    }
}
