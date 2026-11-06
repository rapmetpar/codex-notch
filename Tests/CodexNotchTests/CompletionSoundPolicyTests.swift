import Foundation
import XCTest
@testable import CodexNotch

final class CompletionSoundPolicyTests: XCTestCase {
    private func completion(_ turn: String, cwd: String? = nil) -> CompletedSession {
        let date = Date(timeIntervalSince1970: 100)
        return CompletedSession(session: SessionActivity(threadID: "thread", turnID: turn, cwd: cwd,
            originator: nil, startedAt: date, lastActivityAt: date), completedAt: date)
    }

    func testOptInBatchDedupeCooldownMuteAndStop() {
        var plays = 0
        let policy = CompletionSoundPolicy { plays += 1 }
        let a = completion("a")
        policy.receive([a], enabled: true, muted: false, uptime: 0)
        policy.start()
        policy.receive([a], enabled: false, muted: false, uptime: 1)
        policy.receive([a], enabled: true, muted: false, uptime: 2)
        XCTAssertEqual(plays, 0, "disabled events must not replay after enabling")
        policy.receive([completion("b"), completion("c")], enabled: true, muted: false, uptime: 3)
        XCTAssertEqual(plays, 1)
        policy.receive([completion("b", cwd: "/renamed"), completion("d")], enabled: true, muted: false, uptime: 12)
        XCTAssertEqual(plays, 1)
        policy.receive([completion("d")], enabled: true, muted: false, uptime: 14)
        XCTAssertEqual(plays, 1, "cooldown events must not replay")
        policy.receive([completion("e")], enabled: true, muted: true, uptime: 15)
        policy.receive([completion("f")], enabled: false, muted: false, uptime: 16)
        XCTAssertEqual(plays, 1)
        policy.receive([completion("g")], enabled: true, muted: false, uptime: 17)
        XCTAssertEqual(plays, 2)
        policy.stop()
        policy.receive([completion("h")], enabled: true, muted: false, uptime: 30)
        XCTAssertEqual(plays, 2)
    }
}
