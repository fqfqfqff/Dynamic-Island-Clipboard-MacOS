import XCTest
@testable import AuraCore

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func makeStore() -> (SettingsStore, UserDefaults, String) {
        let defaults = TestDefaults.make()
        return (SettingsStore(defaults: defaults), defaults, TestDefaults.suite)
    }

    func testDefaultsAreSane() {
        let (settings, _, name) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        XCTAssertTrue(settings.showNotch)
        XCTAssertFalse(settings.paused)
        XCTAssertTrue(settings.hideInFullScreen)
        XCTAssertEqual(settings.clipboardLimit, 100)
        XCTAssertTrue(settings.enableMusic)
        XCTAssertEqual(settings.backgroundOpacity, 1)
    }

    func testChangesArePersistedAndReloaded() {
        let (settings, defaults, name) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        settings.expandOnHover = true
        settings.clipboardLimit = 42
        settings.bottomCornerRadius = 30

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.expandOnHover)
        XCTAssertEqual(reloaded.clipboardLimit, 42)
        XCTAssertEqual(reloaded.bottomCornerRadius, 30)
    }

    func testPermissionPromptsAreRememberedAcrossLaunches() {
        let (settings, defaults, name) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        XCTAssertFalse(settings.didAskAccessibility, "на старте разрешение ещё не спрашивали")
        XCTAssertFalse(settings.musicAccessBlocked)

        settings.didAskAccessibility = true
        settings.musicAccessBlocked = true

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.didAskAccessibility, "после перезапуска спрашивать второй раз нельзя")
        XCTAssertTrue(reloaded.musicAccessBlocked)
    }

    func testForgettingPromptsAllowsAskingAgain() {
        let (settings, _, name) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        settings.didAskAccessibility = true
        settings.musicAccessBlocked = true

        settings.forgetPermissionPrompts()

        XCTAssertFalse(settings.didAskAccessibility)
        XCTAssertFalse(settings.musicAccessBlocked)
    }

    func testResetRestoresDefaults() {
        let (settings, _, name) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        settings.paused = true
        settings.enableMusic = false
        settings.clipboardLimit = 10

        settings.resetToDefaults()

        XCTAssertFalse(settings.paused)
        XCTAssertTrue(settings.enableMusic)
        XCTAssertEqual(settings.clipboardLimit, 100)
    }
}

extension SettingsStoreTests {
    /// Каждая настройка обязана пережить перезапуск: пользователь настраивает
    /// вид один раз, а не при каждом запуске.
    func testEveryAppearanceSettingSurvivesRelaunch() {
        let (settings, defaults, name) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        settings.backgroundStyle = "gradient"
        settings.gradientPreset = "ocean"
        settings.glassStyle = "tinted"
        settings.accentSource = "fixed"
        settings.accentHex = "#1E90FF"
        settings.fontDesign = "rounded"
        settings.showcaseLayout = "centered"
        settings.showcaseClock = false
        settings.artworkSize = 140
        settings.artworkCornerRadius = 8
        settings.titleFontSize = 19
        settings.backdropStrength = 0.5
        settings.backdropBlur = 70
        settings.barCount = 7
        settings.showSeekBar = false
        settings.showControls = false
        settings.showRemainingTime = true
        settings.trailingSlotStyle = "progress"

        let reloaded = SettingsStore(defaults: defaults)

        XCTAssertEqual(reloaded.backgroundStyle, "gradient")
        XCTAssertEqual(reloaded.gradientPreset, "ocean")
        XCTAssertEqual(reloaded.glassStyle, "tinted")
        XCTAssertEqual(reloaded.accentSource, "fixed")
        XCTAssertEqual(reloaded.accentHex, "#1E90FF")
        XCTAssertEqual(reloaded.fontDesign, "rounded")
        XCTAssertEqual(reloaded.showcaseLayout, "centered")
        XCTAssertFalse(reloaded.showcaseClock)
        XCTAssertEqual(reloaded.artworkSize, 140)
        XCTAssertEqual(reloaded.artworkCornerRadius, 8)
        XCTAssertEqual(reloaded.titleFontSize, 19)
        XCTAssertEqual(reloaded.backdropStrength, 0.5)
        XCTAssertEqual(reloaded.backdropBlur, 70)
        XCTAssertEqual(reloaded.barCount, 7)
        XCTAssertFalse(reloaded.showSeekBar)
        XCTAssertFalse(reloaded.showControls)
        XCTAssertTrue(reloaded.showRemainingTime)
        XCTAssertEqual(reloaded.trailingSlotStyle, "progress")
    }

    func testIslandBehaviourSettingsSurviveRelaunch() {
        let (settings, defaults, name) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        settings.reactToProximity = false
        settings.proximityReach = 250
        settings.animationSpeed = 1.6
        settings.hoverDelay = 0.4
        settings.autoCollapseAfter = 12
        settings.hintStyle = "line"
        settings.showShadow = false
        settings.showBorder = true

        let reloaded = SettingsStore(defaults: defaults)

        XCTAssertFalse(reloaded.reactToProximity)
        XCTAssertEqual(reloaded.proximityReach, 250)
        XCTAssertEqual(reloaded.animationSpeed, 1.6)
        XCTAssertEqual(reloaded.hoverDelay, 0.4)
        XCTAssertEqual(reloaded.autoCollapseAfter, 12)
        XCTAssertEqual(reloaded.hintStyle, "line")
        XCTAssertFalse(reloaded.showShadow)
        XCTAssertTrue(reloaded.showBorder)
    }
}
