import XCTest
@testable import AuraCore

/// В словаре AppleScript у Spotify ровно одно текстовое поле `artist`, и для
/// трека с несколькими исполнителями оно называет только первого. Остальных
/// приходится брать с публичной страницы трека.
final class SpotifyArtistsTests: XCTestCase {

    func testTrackIDIsTakenFromURI() {
        XCTAssertEqual(
            SpotifyArtists.trackID(from: "spotify:track:0eGsygTp906u18L0Oimnem"),
            "0eGsygTp906u18L0Oimnem"
        )
        XCTAssertNil(SpotifyArtists.trackID(from: "spotify:album:123"))
        XCTAssertNil(SpotifyArtists.trackID(from: "мусор"))
        XCTAssertNil(SpotifyArtists.trackID(from: "spotify:track:"))
    }

    /// Формат описания: «Исполнители · Альбом · Song · Год».
    func testArtistsAreTheFirstPartOfDescription() {
        XCTAssertEqual(
            SpotifyArtists.artists(fromDescription: "Big Baby Tape, kizaru · Dragonborn · Song · 2021"),
            "Big Baby Tape, kizaru"
        )
        XCTAssertEqual(
            SpotifyArtists.artists(fromDescription: "M83 · Hurry Up · Song · 2011"),
            "M83"
        )
        XCTAssertNil(SpotifyArtists.artists(fromDescription: ""))
    }

    /// Замена принимается только если она продолжает то, что уже сказал
    /// AppleScript. Сломается разметка страницы — останется как было,
    /// а не пусто и не мусор.
    func testReplacementMustContinueWhatWeAlreadyKnow() {
        XCTAssertTrue(SpotifyArtists.isBetter("Big Baby Tape, kizaru", than: "Big Baby Tape"))
        XCTAssertFalse(SpotifyArtists.isBetter("Big Baby Tape", than: "Big Baby Tape"),
                       "то же самое менять незачем")
        XCTAssertFalse(SpotifyArtists.isBetter("Совсем другой", than: "Big Baby Tape"),
                       "не продолжение — значит, разбор сломался")
        XCTAssertFalse(SpotifyArtists.isBetter("", than: "Big Baby Tape"))
    }

    func testMetaTagIsExtractedFromRawHTML() {
        let html = """
        <html><head><meta property="og:title" content="Benzomageddon">
        <meta property="og:description" content="Big Baby Tape, kizaru &amp; friends · VARSKVA · Song · 2023">
        </head></html>
        """
        XCTAssertEqual(
            SpotifyArtists.meta(named: "og:description", in: html),
            "Big Baby Tape, kizaru & friends · VARSKVA · Song · 2023"
        )
        XCTAssertNil(SpotifyArtists.meta(named: "og:audio", in: html))
    }
}
