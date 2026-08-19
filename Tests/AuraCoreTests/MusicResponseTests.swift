import XCTest
@testable import AuraCore

final class MusicResponseTests: XCTestCase {
    func testParsesSpotifyAnswerWithArtwork() throws {
        let text = "DINERO\nBig Baby Tape\n215000\n42.5\ntrue\nhttps://i.scdn.co/image/abc"
        let response = try XCTUnwrap(MusicResponse.parse(text, durationDivisor: 1000))

        XCTAssertEqual(response.title, "DINERO")
        XCTAssertEqual(response.artist, "Big Baby Tape")
        XCTAssertEqual(response.duration, 215, "Spotify отдаёт миллисекунды")
        XCTAssertEqual(response.elapsed, 42.5)
        XCTAssertTrue(response.isPlaying)
        XCTAssertEqual(response.artworkURL, "https://i.scdn.co/image/abc")
    }

    func testParsesMusicAnswerWithoutArtwork() throws {
        let response = try XCTUnwrap(
            MusicResponse.parse("Трек\nИсполнитель\n180\n12\nfalse", durationDivisor: 1)
        )
        XCTAssertEqual(response.duration, 180, "Музыка отдаёт секунды")
        XCTAssertFalse(response.isPlaying)
        XCTAssertNil(response.artworkURL)
    }

    func testEmptyTitleMeansNothingIsPlaying() {
        XCTAssertNil(MusicResponse.parse("\n\n0\n0\nfalse", durationDivisor: 1),
                     "пустой заголовок не должен становиться карточкой")
        XCTAssertNil(MusicResponse.parse("   \nартист\n1\n0\ntrue", durationDivisor: 1))
    }

    func testShortAnswerIsRejected() {
        XCTAssertNil(MusicResponse.parse("", durationDivisor: 1))
        XCTAssertNil(MusicResponse.parse("Трек\nАртист", durationDivisor: 1))
    }

    func testMissingArtistIsOptional() throws {
        let response = try XCTUnwrap(MusicResponse.parse("Трек\n\n10\n1\ntrue", durationDivisor: 1))
        XCTAssertNil(response.artist)
    }

    func testBrokenNumbersDoNotCrash() throws {
        let response = try XCTUnwrap(
            MusicResponse.parse("Трек\nАртист\nвосемь\nмного\ntrue", durationDivisor: 1)
        )
        XCTAssertNil(response.duration)
        XCTAssertNil(response.elapsed)
    }
}

extension MusicResponseTests {
    /// Регрессия: в русской локали плееры отдают позицию как «87,094»,
    /// обычный Double(_:) возвращал на этом nil — и полоса длительности
    /// не появлялась вовсе.
    func testParsesNumbersWithLocaleComma() throws {
        let text = "Тесно\nАртист\n132649\n87,09400177002\ntrue"
        let response = try XCTUnwrap(MusicResponse.parse(text, durationDivisor: 1000))

        XCTAssertEqual(response.duration ?? 0, 132.649, accuracy: 0.001)
        XCTAssertEqual(response.elapsed ?? 0, 87.094, accuracy: 0.001)
    }

    func testParsesPlainDotNumbersToo() throws {
        let response = try XCTUnwrap(
            MusicResponse.parse("Трек\nАртист\n180.5\n12.25\ntrue", durationDivisor: 1)
        )
        XCTAssertEqual(response.duration ?? 0, 180.5, accuracy: 0.001)
        XCTAssertEqual(response.elapsed ?? 0, 12.25, accuracy: 0.001)
    }
}
