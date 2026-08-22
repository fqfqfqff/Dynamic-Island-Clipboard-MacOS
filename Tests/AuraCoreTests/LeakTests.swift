import AppKit
import XCTest
@testable import AuraCore

/// Проверки на то, что закрытое перестаёт работать.
///
/// `orderOut` только убирает окно с экрана: оно само, его `NSHostingView`
/// и всё дерево SwiftUI внутри продолжают жить — вместе с таймерами.
/// Витрину достаточно было открыть один раз за сеанс, чтобы приложение
/// до перезапуска тратило процессор на то, чего никто не видит: 1.29%
/// вместо 0.10% и 141 МБ вместо 81.
@MainActor
final class LeakTests: XCTestCase {

    private func makeShowcase() -> ShowcaseWindowController {
        let settings = SettingsStore(defaults: TestDefaults.make())
        let activities = ActivityCenter()
        let lyrics = LyricsProvider()
        let media = NowPlayingProvider(center: activities, settings: settings, lyrics: lyrics)
        return ShowcaseWindowController(media: media, lyrics: lyrics, settings: settings)
    }

    func testHiddenShowcaseKeepsNothingAlive() throws {
        try XCTSkipIf(NSScreen.main == nil, "без экрана витрину не открыть")
        let showcase = makeShowcase()

        showcase.show()
        XCTAssertTrue(showcase.hasWindow, "витрина не открылась — проверять нечего")

        showcase.hide()
        XCTAssertFalse(
            showcase.hasWindow,
            "скрытое окно продолжает жить, а вместе с ним и его таймеры"
        )
    }

    /// Открыть и закрыть много раз: если что-то остаётся, оно накопится.
    func testRepeatedShowAndHideLeavesNothing() throws {
        try XCTSkipIf(NSScreen.main == nil, "без экрана витрину не открыть")
        let showcase = makeShowcase()

        for _ in 0..<20 {
            showcase.show()
            showcase.hide()
        }
        XCTAssertFalse(showcase.hasWindow)
    }
}
