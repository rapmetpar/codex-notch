import Foundation
import XCTest
@testable import CodexNotch

final class TurnOutcomeTests: XCTestCase {
    @MainActor
    func testLifecycleReachesHistoryLabelsWithoutChangingAttentionOrCompactSignal() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = ActiveSessionStore()
        for (thread, terminal) in [("a", RolloutEventKind.taskCompleted(turnID: "t")), ("b", .turnAborted(turnID: "t"))] {
            let events = [RolloutEvent(timestamp: now, kind: .sessionMeta(threadID: thread, cwd: nil, originator: nil)),
                          RolloutEvent(timestamp: now, kind: .taskStarted(turnID: "t")),
                          RolloutEvent(timestamp: now.addingTimeInterval(1), kind: terminal)]
            await store.replace(rolloutID: thread, reduction: ActiveSessionReducer.reduce(events), lastModifiedAt: now)
        }
        let snapshot = await store.snapshot(now: now)
        XCTAssertEqual(Set(snapshot.recentCompletions.map(\.outcome)), Set([.completedEvent, .interrupted]))
        let input = NotchPresentationInput(now: now, isChatGPTFrontmost: false, activeSessions: [], recentCompletions: snapshot.recentCompletions, usage: nil, isHovered: true)
        guard case let .expanded(content) = NotchPresentationReducer.reduce(input) else { return XCTFail() }
        XCTAssertEqual(content.conversations.count, 2)
        for row in content.conversations {
            XCTAssertEqual(row.attention, .unread)
            let view = ConversationRowView(conversation: row, now: now, language: .english, action: {})
            XCTAssertTrue(view.metadataText.contains(row.outcome == .interrupted ? "Interrupted" : "Ended"))
        }
        let aborted = snapshot.recentCompletions.first { $0.outcome == .interrupted }!
        let ended = snapshot.recentCompletions.first { $0.outcome == .completedEvent }!
        XCTAssertFalse(aborted.session.permitsCompletionEffects)
        XCTAssertTrue(ended.session.permitsCompletionEffects)
        XCTAssertFalse(QuotaIndicatorMotion.shouldShowCompletionFirework(activity: .completed, motionEnabled: aborted.session.permitsCompletionEffects))
        var policy = PetCompanionPolicy()
        policy.update(activeSessions: [], completions: [], isHovered: false, now: now)
        policy.update(activeSessions: [], completions: [aborted], isHovered: false, now: now.addingTimeInterval(2))
        if case .celebration = policy.pose { XCTFail("Abort must not celebrate") }
        let renamed = aborted.session.withTitle("same title")
        XCTAssertEqual(renamed.terminalOutcome, .interrupted)
        XCTAssertEqual(ConversationReadReceipt(aborted), ConversationReadReceipt(turnID: "t", completedAt: aborted.completedAt))
    }

    func testMalformedCompletionAndLateAbort() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reduction = ActiveSessionReducer.reduce([
            RolloutEvent(timestamp: now, kind: .sessionMeta(threadID: "thread", cwd: nil, originator: nil)),
            RolloutEvent(timestamp: now, kind: .taskStarted(turnID: "one")),
            RolloutEvent(timestamp: nil, kind: .taskCompleted(turnID: "one")),
            RolloutEvent(timestamp: now, kind: .taskStarted(turnID: "two")),
            RolloutEvent(timestamp: now, kind: .turnAborted(turnID: "one"))
        ])
        XCTAssertEqual(reduction.completed.first?.terminalOutcome, .unknown)
        XCTAssertFalse(reduction.completed[0].permitsCompletionEffects)
        XCTAssertTrue(reduction.successful.isEmpty)
        XCTAssertEqual(reduction.active.map(\.turnID), ["two"])
        for language in AppLanguage.allCases {
            XCTAssertNotEqual(TurnOutcome.completedEvent.label(language: language), TurnOutcome.interrupted.label(language: language))
            XCTAssertFalse(TurnOutcome.unknown.explanation(language: language).isEmpty)
        }
    }
}
