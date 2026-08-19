import XCTest
@testable import AuraCore

@MainActor
final class ActivityCenterTests: XCTestCase {
    private func activity(
        _ id: String,
        priority: Activity.Priority = .normal,
        title: String = "T",
        expiresAt: Date? = nil
    ) -> Activity {
        Activity(id: id, title: title, symbol: "star", tint: .white,
                 priority: priority, expiresAt: expiresAt)
    }

    func testUpsertReplacesInsteadOfDuplicating() {
        let center = ActivityCenter()
        center.upsert(activity("a", title: "Первый"))
        center.upsert(activity("a", title: "Второй"))

        XCTAssertEqual(center.activities.count, 1)
        XCTAssertEqual(center.activities.first?.title, "Второй")
    }

    func testHigherPriorityGoesFirst() {
        let center = ActivityCenter()
        center.upsert(activity("low", priority: .ambient))
        center.upsert(activity("high", priority: .critical))
        center.upsert(activity("mid", priority: .normal))

        XCTAssertEqual(center.activities.map(\.id), ["high", "mid", "low"])
        XCTAssertEqual(center.featured?.id, "high")
    }

    func testCriticalSurvivesCrowding() {
        let center = ActivityCenter()
        center.upsert(activity("critical", priority: .critical))
        for index in 0..<10 {
            center.upsert(activity("noise\(index)", priority: .normal))
        }

        XCTAssertTrue(center.activities.contains { $0.id == "critical" },
                      "критичная активность не должна вытесняться потоком обычных")
        XCTAssertLessThanOrEqual(center.activities.count, 5)
    }

    func testRemoveAndHiddenCount() {
        let center = ActivityCenter()
        center.upsert(activity("a"))
        center.upsert(activity("b"))
        XCTAssertEqual(center.hiddenCount, 1)

        center.remove(id: "a")
        XCTAssertEqual(center.activities.map(\.id), ["b"])
        XCTAssertEqual(center.hiddenCount, 0)

        center.remove(id: "нет такой")
        XCTAssertEqual(center.activities.count, 1)
    }

    func testExpiredActivityIsReportedExpired() {
        let past = activity("old", expiresAt: Date().addingTimeInterval(-1))
        let future = activity("new", expiresAt: Date().addingTimeInterval(60))
        XCTAssertTrue(past.isExpired)
        XCTAssertFalse(future.isExpired)
        XCTAssertFalse(activity("forever").isExpired)
    }
}
