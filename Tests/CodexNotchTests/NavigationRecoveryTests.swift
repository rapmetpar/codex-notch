import XCTest
@testable import CodexNotch

final class NavigationRecoveryTests: XCTestCase {
    func testFailureRetryAndChangedTurnNeverAcknowledgesNewAnswer() {
        var accepted = false
        var current: String? = "turn-a"
        var receipts: [String] = []
        var failures: [ThreadHandoffResult] = []
        let flow = ThreadNavigationRecovery(
            handoff: { _ in accepted ? .accepted : .refused },
            currentTurn: { _ in current },
            acknowledge: { _, turn in receipts.append(turn) },
            showFailure: { _, result, _ in failures.append(result) }
        )
        flow.open(threadID: "thread")
        XCTAssertEqual(failures, [.refused])
        XCTAssertTrue(receipts.isEmpty)
        current = "turn-b"
        accepted = true
        flow.retry(threadID: "thread", capturedTurn: "turn-a")
        XCTAssertTrue(receipts.isEmpty)
        flow.open(threadID: "thread")
        XCTAssertEqual(receipts, ["turn-b"])
    }

    func testInvalidAndUnavailableDoNotOpenOrAcknowledge() {
        let invalid = CodexThreadNavigator(openURL: { _ in XCTFail(); return false }, activateApp: { XCTFail(); return false }, isAppAvailable: { false })
        XCTAssertEqual(invalid.handoff(threadID: "invalid id"), .invalidID)
        XCTAssertEqual(invalid.handoff(threadID: "valid"), .appUnavailable)
    }
}
