import Foundation
import XCTest
@testable import CodexNotch

final class CompactCompletionStoreTests: XCTestCase {
    func testOnlyLiveSuccessfulEventsGenerateSignalsEvenWhenStartAndFinishTogether() {
        let started = Date(timeIntervalSince1970: 100)
        func event(_ seconds: TimeInterval, _ kind: RolloutEventKind) -> RolloutEvent {
            RolloutEvent(timestamp: Date(timeIntervalSince1970: seconds), kind: kind)
        }
        let events: [RolloutEvent] = [event(1, .sessionMeta(threadID: "thread", cwd: nil, originator: nil)),
            event(90, .taskStarted(turnID: "old")), event(95, .taskCompleted(turnID: "old")),
            event(101, .taskStarted(turnID: "short")), event(102, .taskCompleted(turnID: "short")),
            event(103, .taskStarted(turnID: "aborted")), event(104, .turnAborted(turnID: "aborted"))]
        let empty = ActiveSessionReduction(active: [], completed: [])
        let reduction = ActiveSessionReducer.reduce(events)
        let fresh = RolloutActivityMonitor.newSuccessfulCompletions(previous: empty, current: reduction,
            events: events, startedAt: started)
        XCTAssertEqual(fresh.map(\.session.turnID), ["short"])
        XCTAssertTrue(RolloutActivityMonitor.newSuccessfulCompletions(previous: reduction, current: reduction,
            events: events, startedAt: started).isEmpty)
    }

    func testSameTimestampAnonymousSuccessDoesNotTurnAbortIntoSuccess() {
        let date = Date(timeIntervalSince1970: 110)
        let events: [RolloutEvent] = [
            RolloutEvent(timestamp: date, kind: .sessionMeta(threadID: "thread", cwd: nil, originator: nil)),
            RolloutEvent(timestamp: date, kind: .taskStarted(turnID: "first")),
            RolloutEvent(timestamp: date, kind: .taskCompleted(turnID: nil)),
            RolloutEvent(timestamp: date, kind: .taskStarted(turnID: "second")),
            RolloutEvent(timestamp: date, kind: .turnAborted(turnID: "second"))
        ]
        let result = RolloutActivityMonitor.newSuccessfulCompletions(
            previous: ActiveSessionReduction(active: [], completed: []),
            current: ActiveSessionReducer.reduce(events), events: events,
            startedAt: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(result.map(\.session.turnID), ["first"])
    }

    func testFutureDatedHistoryCannotGenerateSignal() {
        let now = Date()
        let future = now.addingTimeInterval(3600)
        let events: [RolloutEvent] = [
            RolloutEvent(timestamp: now, kind: .sessionMeta(threadID: "thread", cwd: nil, originator: nil)),
            RolloutEvent(timestamp: future, kind: .taskStarted(turnID: "future")),
            RolloutEvent(timestamp: future, kind: .taskCompleted(turnID: "future"))
        ]
        let result = RolloutActivityMonitor.newSuccessfulCompletions(
            previous: ActiveSessionReduction(active: [], completed: []),
            current: ActiveSessionReducer.reduce(events), events: events,
            startedAt: now.addingTimeInterval(-60))
        XCTAssertTrue(result.isEmpty)
    }

    func testMetadataRefreshDoesNotRediscoverSuccessfulTurn() {
        let date = Date().addingTimeInterval(-1)
        let before = SessionActivity(threadID: "thread", turnID: "turn", cwd: nil,
            originator: nil, startedAt: date, lastActivityAt: date)
        let after = before.updating(cwd: "/different")
        let old = ActiveSessionReduction(active: [], completed: [before], successful: [before])
        let current = ActiveSessionReduction(active: [], completed: [after], successful: [after])
        let rediscovered = RolloutActivityMonitor.newSuccessfulCompletions(previous: old, current: current,
            events: [], startedAt: date.addingTimeInterval(-1))
        let suite = "CompactCompletionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let signals = CompactCompletionStore(defaults: defaults)
        signals.record(rediscovered)
        let history = CompletedSession(session: after, completedAt: date)
        let state = NotchPresentationReducer.reduce(NotchPresentationInput(now: Date(), isChatGPTFrontmost: false,
            activeSessions: [], recentCompletions: [history], usage: nil, isHovered: false,
            compactCompletionSignals: signals.signals))
        XCTAssertEqual(state, .quotaCompact(nil))
        XCTAssertTrue(signals.signals.isEmpty)
    }

    func testSignalPersistsAndExactReadClearsIt() throws {
        let suite = "CompactCompletionStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSince1970: 100)
        let item = CompletedSession(session: SessionActivity(threadID: "thread", turnID: "turn", cwd: nil,
            originator: nil, startedAt: date, lastActivityAt: date), completedAt: date)
        CompactCompletionStore(defaults: defaults).record([item])
        let restarted = CompactCompletionStore(defaults: defaults)
        XCTAssertEqual(restarted.signals["thread"], ConversationReadReceipt(item))
        restarted.removeViewed(local: [:], native: ["thread": NativeConversationReadReceipt(turnID: "old")])
        XCTAssertNotNil(restarted.signals["thread"])
        restarted.removeViewed(local: [:], native: ["thread": NativeConversationReadReceipt(turnID: "turn")])
        XCTAssertTrue(CompactCompletionStore(defaults: defaults).signals.isEmpty)
    }
}
