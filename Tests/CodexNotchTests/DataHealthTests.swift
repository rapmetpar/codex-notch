import XCTest
@testable import CodexNotch

final class DataHealthTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func snapshot(_ date: Date, used: Double = 25) -> UsageSnapshot {
        UsageSnapshot(windows: [UsageWindow(id: "weekly", kind: .weekly, usedPercent: used)], fetchedAt: date)
    }

    @MainActor
    func testFailureRetainsQuotaAndSuccessTimeThenRetryRecovers() async {
        let model = DataHealth()
        var now = t0
        model.start(at: now)
        defer { model.stop() }
        let initial = snapshot(now)
        let success = expectation(description: "first quota")
        XCTAssertTrue(model.requestUsage(nowProvider: { now }, fetch: { initial }, didFinish: { success.fulfill() }))
        await fulfillment(of: [success], timeout: 2)
        XCTAssertEqual(model.usage.state, .fresh)
        XCTAssertEqual(model.usage.lastSuccessAt, t0)

        now.addTimeInterval(60)
        XCTAssertTrue(model.automaticRefreshIsDue(at: now))
        let failure = expectation(description: "offline quota")
        XCTAssertTrue(model.requestUsage(nowProvider: { now }, fetch: {
            throw NSError(domain: "synthetic", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bearer SYNTHETIC_SECRET /synthetic/private/path"])
        }, didFinish: { failure.fulfill() }))
        await fulfillment(of: [failure], timeout: 2)
        XCTAssertEqual(model.usageSnapshot?.weeklyWindow?.remainingPercent, 75)
        XCTAssertEqual(model.usage.lastSuccessAt, t0)
        XCTAssertEqual(model.usage.state, .stale)
        XCTAssertTrue(model.usage.lastCheckFailed)
        XCTAssertFalse(model.automaticRefreshIsDue(at: now.addingTimeInterval(59)))
        XCTAssertTrue(model.automaticRefreshIsDue(at: now.addingTimeInterval(60)))
        for language in AppLanguage.allCases {
            let visible = DataHealthText.title(language) + DataHealthText.failure(language)
                + DataHealthText.lastSuccess(model.usage.lastSuccessAt, language: language)
                + model.usage.state.title(language: language)
            XCTAssertFalse(visible.contains("SYNTHETIC_SECRET"))
            XCTAssertFalse(visible.contains("/synthetic"))
        }
        now.addTimeInterval(10)
        let recovered = snapshot(now, used: 40)
        let retry = expectation(description: "recovered quota")
        XCTAssertTrue(model.requestUsage(nowProvider: { now }, fetch: { recovered }, didFinish: { retry.fulfill() }))
        await fulfillment(of: [retry], timeout: 2)
        XCTAssertEqual(model.usageSnapshot?.weeklyWindow?.remainingPercent, 60)
        XCTAssertEqual(model.usage.lastSuccessAt, now)
        XCTAssertEqual(model.usage.state, .fresh)
        XCTAssertFalse(model.usage.lastCheckFailed)
    }

    @MainActor
    func testRepeatedRetryIsSingleFlightAndRespectsTenSecondCooldown() async {
        let model = DataHealth()
        var now = t0
        model.start(at: now)
        defer { model.stop() }
        let initial = snapshot(now)
        let started = expectation(description: "request started")
        let finished = expectation(description: "request finished")
        var continuation: CheckedContinuation<UsageSnapshot, Never>?
        var requests = 0
        let fetch: () async throws -> UsageSnapshot = {
            requests += 1
            return await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
        }
        XCTAssertTrue(model.requestUsage(nowProvider: { now }, fetch: fetch, didFinish: { finished.fulfill() }))
        for _ in 0..<10 { XCTAssertFalse(model.requestUsage(nowProvider: { now }, fetch: fetch)) }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(model.usage.state, .loading)
        XCTAssertFalse(model.automaticRefreshIsDue(at: now.addingTimeInterval(300)))
        XCTAssertFalse(model.requestUsage(nowProvider: { now.addingTimeInterval(300) }, fetch: fetch))
        continuation?.resume(returning: initial)
        await fulfillment(of: [finished], timeout: 2)
        now.addTimeInterval(9.999)
        model.updateClock(now)
        XCTAssertFalse(model.canRetry)
        XCTAssertFalse(model.requestUsage(nowProvider: { now }, fetch: fetch))
        now = t0.addingTimeInterval(10)
        model.updateClock(now)
        XCTAssertTrue(model.canRetry)
        let next = expectation(description: "retry at boundary")
        XCTAssertTrue(model.requestUsage(nowProvider: { now }, fetch: {
            requests += 1
            return initial
        }, didFinish: { next.fulfill() }))
        await fulfillment(of: [next], timeout: 2)
        XCTAssertEqual(requests, 2)
    }

    @MainActor
    func testCancelledOldGenerationCannotReplaceNewQuotaOrHealth() async {
        let model = DataHealth()
        model.start(at: t0)
        defer { model.stop() }
        let old = snapshot(t0, used: 99)
        let new = snapshot(t0.addingTimeInterval(60), used: 10)
        let started = expectation(description: "blocked old client")
        let returned = expectation(description: "cancel-insensitive old client returned")
        let ignored = expectation(description: "old completion must be ignored")
        ignored.isInverted = true
        var continuation: CheckedContinuation<UsageSnapshot, Never>?
        model.requestUsage(nowProvider: { self.t0 }, fetch: {
            let value = await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
            returned.fulfill()
            return value
        }, didFinish: { ignored.fulfill() })
        await fulfillment(of: [started], timeout: 2)
        model.stop()
        XCTAssertFalse(model.canRetry)
        model.start(at: new.fetchedAt)
        let finished = expectation(description: "new generation")
        model.requestUsage(nowProvider: { new.fetchedAt }, fetch: { new }, didFinish: { finished.fulfill() })
        await fulfillment(of: [finished], timeout: 2)
        continuation?.resume(returning: old)
        await fulfillment(of: [returned, ignored], timeout: 0.15)
        XCTAssertEqual(model.usageSnapshot, new)
        XCTAssertEqual(model.usage.state, .fresh)
        XCTAssertEqual(model.usage.lastSuccessAt, new.fetchedAt)
    }

    @MainActor
    func testInitialFailureDoesNotInventZeroAndSourcesRemainIndependent() async {
        let model = DataHealth()
        model.start(at: t0)
        defer { model.stop() }
        model.recordRollouts(.success, at: t0)
        model.recordNativeRead(.failure, at: t0)
        let failed = expectation(description: "first failure")
        model.requestUsage(nowProvider: { self.t0 }, fetch: { throw URLError(.notConnectedToInternet) }, didFinish: { failed.fulfill() })
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertNil(model.usageSnapshot)
        XCTAssertNil(model.usage.lastSuccessAt)
        XCTAssertEqual(model.usage.state, .unavailable)
        XCTAssertEqual(model.rollouts.state, .fresh)
        XCTAssertEqual(model.nativeRead.state, .unavailable)
        model.recordNativeRead(.idle, at: t0)
        XCTAssertEqual(model.nativeRead.state, .idle)
    }

    func testClockAgesSuccessfulChecksWithoutChangingSourceValues() {
        var health = DataSourceHealth()
        health.record(.success, at: t0)
        for interval in [DataHealth.usageStaleAfter, DataHealth.rolloutStaleAfter, DataHealth.nativeReadStaleAfter] {
            XCTAssertEqual(health.state(at: t0.addingTimeInterval(interval - 0.01), staleAfter: interval), .fresh)
            XCTAssertEqual(health.state(at: t0.addingTimeInterval(interval), staleAfter: interval), .stale)
        }
        XCTAssertEqual(health.lastSuccessAt, t0)
        XCTAssertFalse(health.lastCheckFailed)
        health.record(.failure, at: t0.addingTimeInterval(1))
        XCTAssertEqual(health.state, .stale)
        XCTAssertEqual(health.lastSuccessAt, t0)
    }

    func testStatusCopySupportsAllLanguagesAndKeepsExactSuccessTime() {
        for state in DataHealthState.allCases {
            XCTAssertEqual(Set(AppLanguage.allCases.map { state.title(language: $0) }).count, 3)
        }
        for language in AppLanguage.allCases {
            XCTAssertFalse(DataHealthText.title(language).isEmpty)
            XCTAssertNotEqual(DataHealthText.lastSuccess(nil, language: language), DataHealthText.lastSuccess(t0, language: language))
            XCTAssertNotEqual(DataHealthText.lastSuccess(t0, language: language), DataHealthText.lastSuccess(t0.addingTimeInterval(1), language: language))
        }
    }
}
