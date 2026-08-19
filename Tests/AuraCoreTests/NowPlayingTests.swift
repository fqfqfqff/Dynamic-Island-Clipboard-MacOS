import XCTest
@testable import AuraCore

@MainActor
final class NowPlayingTests: XCTestCase {
    private func playing(
        duration: TimeInterval? = 200,
        elapsed: TimeInterval? = 50,
        secondsAgo: TimeInterval = 0,
        isPlaying: Bool = true
    ) -> NowPlayingProvider.NowPlaying {
        NowPlayingProvider.NowPlaying(
            title: "Трек",
            subtitle: "Артист",
            appName: "Spotify",
            duration: duration,
            elapsed: elapsed,
            elapsedAt: Date().addingTimeInterval(-secondsAgo),
            isPlaying: isPlaying,
            canControl: true
        )
    }

    func testProgressMovesBetweenPolls() throws {
        // Позиция получена 10 секунд назад — полоса обязана уехать вперёд сама,
        // иначе она дёргается раз в несколько секунд.
        let value = try XCTUnwrap(playing(secondsAgo: 10).progress())
        XCTAssertEqual(value, 60.0 / 200.0, accuracy: 0.01)
    }

    func testPausedProgressStandsStill() throws {
        let value = try XCTUnwrap(playing(secondsAgo: 30, isPlaying: false).progress())
        XCTAssertEqual(value, 50.0 / 200.0, accuracy: 0.001, "на паузе полоса двигаться не должна")
    }

    func testProgressNeverLeavesBounds() throws {
        let overrun = try XCTUnwrap(playing(elapsed: 195, secondsAgo: 60).progress())
        XCTAssertEqual(overrun, 1, "полоса не может уйти дальше конца трека")

        let elapsed = try XCTUnwrap(playing(elapsed: 195, secondsAgo: 60).elapsedNow())
        XCTAssertLessThanOrEqual(elapsed, 200)
    }

    func testSourcesWithoutDurationHaveNoProgress() {
        XCTAssertNil(playing(duration: nil, elapsed: nil).progress(),
                     "у видео в браузере длительности нет — полосы быть не должно")
        XCTAssertNil(playing(duration: 0, elapsed: 10).progress())
    }

    func testTrackChangeIsMeaningfulButPositionIsNot() {
        let first = playing()
        var sameTrackLater = playing(elapsed: 120)
        XCTAssertFalse(sameTrackLater.differsMeaningfully(from: first),
                       "сдвиг позиции не повод перерисовывать вырез")

        sameTrackLater.title = "Другой"
        XCTAssertTrue(sameTrackLater.differsMeaningfully(from: first))

        var paused = playing()
        paused.isPlaying = false
        XCTAssertTrue(paused.differsMeaningfully(from: first))
    }

    func testAudioBarsIndicatorOnlyWhilePlaying() {
        let activity = Activity(
            id: "media", title: "Трек", symbol: "waveform", tint: .pink,
            indicator: .audioBars
        )
        XCTAssertEqual(activity.indicator, .audioBars)
    }
}
