import Foundation
import XCTest
@testable import CodexNotch

final class CompactUnreadCompletionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func completion(_ thread: String, turn: String = "turn", offset: TimeInterval = 0) -> CompletedSession {
        let date = now.addingTimeInterval(offset)
        return CompletedSession(session: SessionActivity(threadID: thread, turnID: turn,
            cwd: nil, originator: nil, startedAt: date, lastActivityAt: date), completedAt: date)
    }

    func testReadCompletionDisappearsFromCompactButRemainsInHistory() {
        let finished = completion("thread")
        var input = NotchPresentationInput(now: now, isChatGPTFrontmost: false,
            activeSessions: [], recentCompletions: [finished], usage: nil, isHovered: false,
            compactCompletionSignals: ["thread": ConversationReadReceipt(finished)])
        XCTAssertEqual(NotchPresentationReducer.reduce(input), .completedCompact(finished.session, usage: nil))
        input.readReceipts = ["thread": ConversationReadReceipt(finished)]
        XCTAssertEqual(NotchPresentationReducer.reduce(input), .quotaCompact(nil))
        input = NotchPresentationInput(now: now, isChatGPTFrontmost: false,
            activeSessions: [], recentCompletions: [finished], usage: nil, isHovered: true,
            readReceipts: input.readReceipts)
        guard case let .expanded(content) = NotchPresentationReducer.reduce(input) else { return XCTFail("Expected expanded") }
        XCTAssertEqual(content.conversations.first?.attention, .viewed)
    }

    func testNativeReadSkipsViewedAndShowsOlderUnreadThenClears() {
        let newest = completion("newest")
        let older = completion("older", offset: -30)
        var input = NotchPresentationInput(now: now, isChatGPTFrontmost: false,
            activeSessions: [], recentCompletions: [newest, older], usage: nil, isHovered: false,
            nativeReadReceipts: ["newest": NativeConversationReadReceipt(turnID: "turn")],
            compactCompletionSignals: ["newest": ConversationReadReceipt(newest), "older": ConversationReadReceipt(older)])
        XCTAssertEqual(NotchPresentationReducer.reduce(input), .completedCompact(older.session, usage: nil))
        input.nativeReadReceipts["older"] = NativeConversationReadReceipt(turnID: "turn")
        XCTAssertEqual(NotchPresentationReducer.reduce(input), .quotaCompact(nil))
        input.nativeReadReceipts["newest"] = NativeConversationReadReceipt(turnID: "old-turn")
        XCTAssertEqual(NotchPresentationReducer.reduce(input), .completedCompact(newest.session, usage: nil))
    }

    func testExactNativeUnreadCanShowCompactWithoutObservedSignal() {
        let finished = completion("thread")
        var input = NotchPresentationInput(now: now, isChatGPTFrontmost: false,
            activeSessions: [], recentCompletions: [finished], usage: nil, isHovered: false,
            nativeReadReceipts: ["thread": NativeConversationReadReceipt(turnID: "turn", isRead: false)])
        XCTAssertEqual(NotchPresentationReducer.reduce(input), .completedCompact(finished.session, usage: nil))
        input.nativeReadReceipts["thread"] = NativeConversationReadReceipt(turnID: "old", isRead: false)
        XCTAssertEqual(NotchPresentationReducer.reduce(input), .quotaCompact(nil))
        input.nativeReadReceipts["thread"] = NativeConversationReadReceipt(turnID: "turn", isRead: true)
        XCTAssertEqual(NotchPresentationReducer.reduce(input), .quotaCompact(nil))
        input.nativeReadReceipts["thread"] = NativeConversationReadReceipt(turnID: "turn", isRead: false)
        input.readReceipts["thread"] = ConversationReadReceipt(finished)
        XCTAssertEqual(NotchPresentationReducer.reduce(input), .quotaCompact(nil))
    }

    func testHistoryWithoutSignalDoesNotCreateCompactCheck() {
        let finished = completion("historical")
        let input = NotchPresentationInput(now: now, isChatGPTFrontmost: false,
            activeSessions: [], recentCompletions: [finished], usage: nil, isHovered: false)
        XCTAssertEqual(NotchPresentationReducer.reduce(input), .quotaCompact(nil))
    }

    func testRunningOverridesUnreadCompletion() {
        let finished = completion("finished")
        let running = completion("running").session
        let input = NotchPresentationInput(now: now, isChatGPTFrontmost: false,
            activeSessions: [running], recentCompletions: [finished], usage: nil, isHovered: false)
        XCTAssertEqual(NotchPresentationReducer.reduce(input), .workingCompact(primary: running, count: 1, usage: nil))
    }
}
