import CoreAudio
import XCTest
@testable import AuraCore

/// Выбор источника звука. Обе проверяемые здесь ошибки видел владелец:
/// музыка из Chrome не подхватывалась вовсе, а Telegram показывался плеером
/// просто потому, что был открыт.
final class AudioSourceTests: XCTestCase {

    // MARK: - Вспомогательный процесс → приложение

    /// Chrome играет не из себя, а из вспомогательного процесса, лежащего
    /// внутри собственного бандла. Брать нужно внешний `.app`, иначе
    /// в вырезе оказывается «Google Chrome Helper», который ни на что
    /// не похож и ничего про вкладку не знает.
    func testChromeHelperResolvesToChrome() {
        let helper = URL(fileURLWithPath:
            "/Applications/Google Chrome.app/Contents/Frameworks/"
            + "Google Chrome Framework.framework/Versions/141.0.7390.55/Helpers/"
            + "Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)")

        XCTAssertEqual(
            AudioProcessMonitor.outermostApplication(helper)?.path,
            "/Applications/Google Chrome.app"
        )
    }

    func testPlainApplicationResolvesToItself() {
        let binary = URL(fileURLWithPath: "/Applications/Spotify.app/Contents/MacOS/Spotify")
        XCTAssertEqual(
            AudioProcessMonitor.outermostApplication(binary)?.path,
            "/Applications/Spotify.app"
        )
    }

    func testDaemonWithoutBundleHasNoApplication() {
        let binary = URL(fileURLWithPath: "/usr/sbin/coreaudiod")
        XCTAssertNil(AudioProcessMonitor.outermostApplication(binary))
    }

    // MARK: - Важность источника

    private func source(
        _ name: String,
        kind: AudioProcessMonitor.Source.Kind,
        bundleID: String? = nil,
        pid: pid_t = 1
    ) -> AudioProcessMonitor.Source {
        AudioProcessMonitor.Source(
            objectID: AudioObjectID(pid),
            pid: pid,
            bundleID: bundleID ?? "test.\(name)",
            name: name,
            kind: kind
        )
    }

    /// Раньше брался просто первый в списке, а порядок его задаёт CoreAudio —
    /// то есть, по сути, случай. Мессенджер выигрывал у браузера регулярно.
    func testPlayerBeatsBrowserBeatsApplication() {
        let list = [
            source("Telegram", kind: .application),
            source("Google Chrome", kind: .browser),
            source("Spotify", kind: .player),
        ]
        XCTAssertEqual(AudioProcessMonitor.ranked(list).map(\.name),
                       ["Spotify", "Google Chrome", "Telegram"])
        XCTAssertEqual(AudioProcessMonitor.preferred(from: list)?.name, "Spotify")
    }

    func testHelperLosesToEveryone() {
        let list = [
            source("Служебный процесс", kind: .helper),
            source("Telegram", kind: .application),
        ]
        XCTAssertEqual(AudioProcessMonitor.preferred(from: list)?.name, "Telegram")
    }

    /// AirPlay — посредник: если рядом звучит своё приложение, показывать
    /// нужно его, а не «звук с устройства».
    func testAirPlayGoesLast() {
        let list = [
            source("Пункт управления", kind: .application, bundleID: "com.apple.controlcenter"),
            source("Telegram", kind: .application),
        ]
        XCTAssertEqual(AudioProcessMonitor.preferred(from: list)?.name, "Telegram")
    }

    func testAirPlayStillWinsWhenItIsAlone() {
        let list = [
            source("Пункт управления", kind: .application, bundleID: "com.apple.controlcenter")
        ]
        XCTAssertEqual(AudioProcessMonitor.preferred(from: list)?.name, "Пункт управления")
    }
}
