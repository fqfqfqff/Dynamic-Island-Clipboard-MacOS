import XCTest
@testable import AuraCore

/// Падение при запуске — худший вид поломки: приложение не успевает показать
/// ни настроек, ни меню, и починить его можно только из терминала. Ровно так
/// вело себя падение на музыке: тап спектра открывался сразу.
@MainActor
final class SafeModeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SafeMode.reset()
    }

    override func tearDown() {
        SafeMode.reset()
        super.tearDown()
    }

    func testTwoFailedLaunchesAreNotEnough() {
        SafeMode.beginLaunch()
        SafeMode.beginLaunch()
        XCTAssertFalse(SafeMode.isActive, "два падения — ещё не закономерность")
    }

    func testThirdFailedLaunchTurnsSourcesOff() {
        for _ in 0..<SafeMode.threshold { SafeMode.beginLaunch() }
        XCTAssertTrue(SafeMode.isActive)
    }

    /// Приложение прожило достаточно — прошлые неудачи больше не в счёт,
    /// иначе три случайных падения за год сложились бы в аварийный режим.
    func testSurvivedLaunchForgetsThePast() {
        for _ in 0..<SafeMode.threshold { SafeMode.beginLaunch() }
        SafeMode.markSurvived()

        SafeMode.beginLaunch()
        XCTAssertFalse(SafeMode.isActive)
        XCTAssertEqual(SafeMode.failedLaunches, 1)
    }

    func testUserCanLeaveSafeMode() {
        for _ in 0..<SafeMode.threshold { SafeMode.beginLaunch() }
        SafeMode.reset()
        XCTAssertFalse(SafeMode.isActive)
    }
}
