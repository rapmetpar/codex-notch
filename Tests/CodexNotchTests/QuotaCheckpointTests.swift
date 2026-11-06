import XCTest
@testable import CodexNotch

final class QuotaCheckpointTests: XCTestCase {
    func testIndependentWindowsAndInvalidation() {
        let now = Date(timeIntervalSince1970: 1_000)
        let reset = now.addingTimeInterval(1_000)
        func window(_ id: String, _ kind: UsageWindowKind, _ remaining: Double, _ resetAt: Date? = nil) -> UsageWindow {
            UsageWindow(id: id, kind: kind, usedPercent: 100 - remaining, resetAt: resetAt ?? reset)
        }
        let five = UsageWindowKind.rolling(hours: 5)
        let model = QuotaCheckpoint()
        model.update(UsageSnapshot(windows: [window("a", five, 80), window("b", .weekly, 90)], fetchedAt: now))
        model.start(now: now)
        model.update(UsageSnapshot(windows: [window("a", five, 67), window("b", .weekly, 85)], fetchedAt: now.addingTimeInterval(60)))
        XCTAssertEqual(model.comparison(kind: five, now: now.addingTimeInterval(60)), .change(-13))
        XCTAssertEqual(model.comparison(kind: .weekly, now: now.addingTimeInterval(60)), .change(-5))
        model.failed()
        XCTAssertEqual(model.comparison(kind: five, now: now.addingTimeInterval(60)), .stale)
        model.update(UsageSnapshot(windows: [window("a", five, 100), window("b", .weekly, 85, reset.addingTimeInterval(1))], fetchedAt: now.addingTimeInterval(61)))
        XCTAssertEqual(model.comparison(kind: five, now: now.addingTimeInterval(61)), .incomparable)
        XCTAssertEqual(model.comparison(kind: .weekly, now: now.addingTimeInterval(61)), .incomparable)
        XCTAssertEqual(model.comparison(kind: five, now: now.addingTimeInterval(200)), .stale)
        model.clear()
        XCTAssertEqual(model.comparison(kind: five, now: now), .noCheckpoint)
        model.start(now: now.addingTimeInterval(61))
        model.stop()
        XCTAssertNil(model.baseline)
        XCTAssertNil(model.snapshot)
    }

    func testMissingResetWindowIdentityAndExpiredResetCannotCompare() {
        let now = Date(timeIntervalSince1970: 1_000)
        let model = QuotaCheckpoint()
        let old = UsageWindow(id: "x", kind: .weekly, usedPercent: 20, resetAt: now.addingTimeInterval(30))
        model.update(UsageSnapshot(windows: [old], fetchedAt: now))
        model.start(now: now)
        model.update(UsageSnapshot(windows: [], fetchedAt: now))
        XCTAssertEqual(model.comparison(kind: .weekly, now: now), .unavailable)
        for next in [UsageWindow(id: "x", kind: .weekly, usedPercent: 30), UsageWindow(id: "y", kind: .weekly, usedPercent: 30, resetAt: old.resetAt)] {
            model.update(UsageSnapshot(windows: [next], fetchedAt: now))
            XCTAssertEqual(model.comparison(kind: .weekly, now: now), .incomparable)
        }
        model.update(UsageSnapshot(windows: [old], fetchedAt: now))
        XCTAssertEqual(model.comparison(kind: .weekly, now: now.addingTimeInterval(30)), .incomparable)
    }
}
