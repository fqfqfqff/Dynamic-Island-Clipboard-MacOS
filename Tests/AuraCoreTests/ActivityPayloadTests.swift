import XCTest
@testable import AuraCore

final class ActivityPayloadTests: XCTestCase {
    private func payload(
        progress: Double? = nil,
        text: String? = nil,
        pulse: Bool? = nil,
        ttl: Double? = nil,
        priority: String? = nil,
        tint: String? = nil
    ) -> ActivityPayload {
        ActivityPayload(
            id: "job", title: "Задача", subtitle: nil, symbol: nil, tint: tint,
            progress: progress, text: text, pulse: pulse, ttl: ttl, priority: priority
        )
    }

    func testExternalActivitiesGetNamespacedID() {
        XCTAssertEqual(payload().makeActivity().id, "external.job",
                       "внешние id не должны сталкиваться со встроенными")
    }

    func testIndicatorPrefersProgressOverText() {
        let activity = payload(progress: 0.5, text: "3/7").makeActivity()
        XCTAssertEqual(activity.indicator, .progress(0.5))
    }

    func testIndicatorFallsBackToTextThenPulse() {
        XCTAssertEqual(payload(text: "3/7").makeActivity().indicator, .text("3/7"))
        XCTAssertEqual(payload(pulse: true).makeActivity().indicator, .pulse)
        XCTAssertEqual(payload().makeActivity().indicator, Activity.Indicator.none)
    }

    func testPriorityParsing() {
        XCTAssertEqual(payload(priority: "critical").makeActivity().priority, .critical)
        XCTAssertEqual(payload(priority: "ambient").makeActivity().priority, .ambient)
        XCTAssertEqual(payload(priority: "чепуха").makeActivity().priority, .normal,
                       "неизвестный приоритет должен становиться обычным, а не падать")
    }

    func testTTLBecomesExpiryInFuture() {
        let activity = payload(ttl: 30).makeActivity()
        let seconds = activity.expiresAt?.timeIntervalSinceNow ?? 0
        XCTAssertTrue(seconds > 25 && seconds <= 30, "ожидали ~30 секунд, получили \(seconds)")
    }

    func testNoTTLMeansNoExpiry() {
        XCTAssertNil(payload().makeActivity().expiresAt)
    }
}
