import AppKit
import SwiftUI
import XCTest
@testable import CodexNotch

final class ReaderWindowTests: XCTestCase {
    @MainActor
    func testSharedSnapshotKeepsLimitAndExactNavigation() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let rows = (0..<20).map { index in
            let session = SessionActivity(threadID: "thread-\(index)", turnID: "turn", title: "Long title \(index)",
                cwd: "/demo", originator: nil, startedAt: now, lastActivityAt: now)
            return ConversationSummary(session: session, activity: .completed(completedAt: now))
        }
        let content = ExpandedContent(sessions: [], conversations: rows, headerConversation: rows.first, usage: nil)
        let model = ReaderWindowModel()
        var opened: String?
        model.openThread = { opened = $0 }
        model.content = content.limitingRecentConversations(to: .twenty)
        XCTAssertEqual(model.content.conversations.count, 20)
        model.openThread(model.content.conversations[19].threadID)
        XCTAssertEqual(opened, "thread-19")
        model.content = content.limitingRecentConversations(to: .none)
        XCTAssertTrue(model.content.projectSections.isEmpty)
    }
}
