import XCTest
@testable import CodexNotch

final class ConversationQueryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func row(_ index: Int, title: String, project: String, running: Bool = false, viewed: Bool = false) -> ConversationSummary {
        let session = SessionActivity(threadID: "thread-\(index)", turnID: "turn-\(index)", title: title,
            cwd: nil, originator: nil, startedAt: now, lastActivityAt: now)
        return ConversationSummary(session: session, activity: running ? .running(startedAt: now) : .completed(completedAt: now),
            isViewed: viewed, project: ConversationProject(id: "project-\(index)", name: project))
    }

    func testBoundedMultilingualSearchClearAndLiveStatus() {
        var rows = (0..<20).map { row($0, title: "Synthetic \($0)", project: "Work") }
        rows[2] = row(2, title: "Проект Альфа", project: "Работа", running: true)
        rows[10] = row(10, title: "测试聊天", project: "项目")
        rows[19] = row(19, title: "Final Match", project: "Research", viewed: true)
        XCTAssertEqual(ConversationQuery(text: "альфа").matching(rows, language: .russian).map(\.threadID), ["thread-2"])
        XCTAssertEqual(ConversationQuery(text: "项目").matching(rows, language: .chinese).map(\.threadID), ["thread-10"])
        XCTAssertEqual(ConversationQuery(text: "research").matching(rows, language: .english).map(\.threadID), ["thread-19"])
        XCTAssertEqual(ConversationQuery().matching(rows, language: .english), rows)
        XCTAssertEqual(ConversationQuery(attention: .running).matching(rows, language: .english).map(\.threadID), ["thread-2"])
        rows[2] = row(2, title: "Проект Альфа", project: "Работа", viewed: true)
        XCTAssertTrue(ConversationQuery(attention: .running).matching(rows, language: .english).isEmpty)
        XCTAssertEqual(ConversationQuery(attention: .viewed).matching(rows, language: .english).map(\.threadID), ["thread-2", "thread-19"])
        XCTAssertTrue(ConversationQuery(text: "match").matching([], language: .english).isEmpty)
        XCTAssertTrue(ConversationQuery(text: "match").matching(Array(rows.prefix(5)), language: .english).isEmpty)
    }
    func testOnlyExplicitSelectionNavigatesWithinCurrentSnapshot() {
        let model = ConversationSearchModel()
        model.conversations = (0..<20).map { row($0, title: "Chat \($0)", project: "Project") }
        var opened: [String] = []
        model.onOpen = { opened.append($0) }
        _ = ConversationQuery(text: "Chat 19").matching(model.conversations, language: .english)
        XCTAssertTrue(opened.isEmpty)
        model.open("thread-19")
        XCTAssertEqual(opened, ["thread-19"])
        model.conversations = []
        model.open("thread-19")
        XCTAssertEqual(opened, ["thread-19"])
    }

}
