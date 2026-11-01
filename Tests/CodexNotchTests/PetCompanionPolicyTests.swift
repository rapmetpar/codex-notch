import XCTest
@testable import CodexNotch

final class PetCompanionPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)
    private func session(_ turn: String = "turn") -> SessionActivity {
        SessionActivity(threadID: "thread", turnID: turn, title: "Synthetic task", cwd: nil,
            originator: nil, startedAt: start, lastActivityAt: start)
    }
    private func completion(_ turn: String = "turn", at date: Date) -> CompletedSession {
        CompletedSession(session: session(turn), completedAt: date)
    }

    func testStartupAndHistoricalDiscoveryNeverCelebrate() {
        var policy = PetCompanionPolicy()
        let old = completion(at: start.addingTimeInterval(-10))
        policy.update(activeSessions: [], completions: [old], isHovered: false, now: start)
        XCTAssertEqual(policy.pose, .idle)
        policy.update(activeSessions: [], completions: [old, completion("older", at: start.addingTimeInterval(-20))],
            isHovered: false, now: start.addingTimeInterval(1))
        XCTAssertEqual(policy.pose, .idle)
    }

    func testActualCompletionCelebratesOnceAndHoverOrRerenderDoesNotReplay() {
        var policy = PetCompanionPolicy()
        policy.update(activeSessions: [session()], completions: [], isHovered: false, now: start)
        XCTAssertEqual(policy.pose, .work)
        let fresh = completion(at: start.addingTimeInterval(1))
        policy.update(activeSessions: [], completions: [fresh], isHovered: false, now: start.addingTimeInterval(1))
        XCTAssertEqual(policy.pose, .celebration(token: PetCompletionKey(fresh).token))
        policy.update(activeSessions: [], completions: [fresh], isHovered: true, now: start.addingTimeInterval(1.2))
        XCTAssertEqual(policy.pose, .celebration(token: PetCompletionKey(fresh).token))
        policy.update(activeSessions: [], completions: [fresh], isHovered: true, now: start.addingTimeInterval(3))
        XCTAssertEqual(policy.pose, .idle)
        policy.update(activeSessions: [], completions: [fresh], isHovered: false, now: start.addingTimeInterval(4))
        XCTAssertEqual(policy.pose, .idle)
        let next = completion("next", at: start.addingTimeInterval(5))
        policy.update(activeSessions: [], completions: [next, fresh], isHovered: false, now: start.addingTimeInterval(5))
        XCTAssertEqual(policy.pose, .celebration(token: PetCompletionKey(next).token))
    }

    func testRunningAlwaysWinsAndSuppressedCompletionDoesNotReplayAfterWorkEnds() {
        var policy = PetCompanionPolicy()
        policy.update(activeSessions: [session()], completions: [], isHovered: false, now: start)
        let fresh = completion(at: start.addingTimeInterval(1))
        policy.update(activeSessions: [session("other")], completions: [fresh], isHovered: true, now: start.addingTimeInterval(1))
        XCTAssertEqual(policy.pose, .work)
        policy.update(activeSessions: [], completions: [fresh], isHovered: false, now: start.addingTimeInterval(2))
        XCTAssertEqual(policy.pose, .idle)
    }

    func testGreetingRequiresEntryAndCooldownAndIdleHasRareWalks() {
        var policy = PetCompanionPolicy()
        policy.update(activeSessions: [], completions: [], isHovered: false, now: start)
        policy.update(activeSessions: [], completions: [], isHovered: true, now: start.addingTimeInterval(1))
        guard case .greeting = policy.pose else { return XCTFail("First hover should greet") }
        policy.update(activeSessions: [], completions: [], isHovered: false, now: start.addingTimeInterval(3))
        policy.update(activeSessions: [], completions: [], isHovered: true, now: start.addingTimeInterval(4))
        XCTAssertEqual(policy.pose, .idle)
        policy.update(activeSessions: [], completions: [], isHovered: true, now: start.addingTimeInterval(21))
        XCTAssertEqual(policy.pose, .walkRight)
        policy.update(activeSessions: [], completions: [], isHovered: false, now: start.addingTimeInterval(31))
        policy.update(activeSessions: [], completions: [], isHovered: true, now: start.addingTimeInterval(32))
        guard case .greeting = policy.pose else { return XCTFail("Cooldown should allow another greeting") }
        policy.update(activeSessions: [], completions: [], isHovered: true, now: start.addingTimeInterval(45))
        XCTAssertEqual(policy.pose, .walkLeft)
    }

    func testCameraSceneAndBothMotionSwitchesHaveExplicitBoundaries() {
        for style in FloatingCenterStyle.allCases {
            XCTAssertFalse(PetCompanionLayout.showsScene(layout: .notch, expanded: false, floatingStyle: style))
            XCTAssertTrue(PetCompanionLayout.showsScene(layout: .notch, expanded: false, floatingStyle: style,
                physicalWingEnabled: true))
            XCTAssertFalse(PetCompanionLayout.showsScene(layout: .notch, expanded: true, floatingStyle: style))
            XCTAssertFalse(PetCompanionLayout.showsScene(layout: .floatingBar, expanded: true, floatingStyle: style))
            XCTAssertEqual(PetCompanionLayout.showsScene(layout: .floatingBar, expanded: false, floatingStyle: style), style == .pet)
        }
        for app in [true, false] { for system in [true, false] { for visible in [true, false] {
            XCTAssertEqual(PetCompanionLayout.allowsMotion(appEnabled: app, reduceMotion: system, visible: visible),
                app && !system && visible)
        } } }
    }
}
