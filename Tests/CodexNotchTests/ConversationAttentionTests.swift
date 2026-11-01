import AppKit
import SwiftUI
import XCTest
@testable import CodexNotch

final class ConversationAttentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func completion(thread: String = "thread", turn: String = "turn", offset: TimeInterval = 0) -> CompletedSession {
        CompletedSession(session: SessionActivity(
            threadID: thread, turnID: turn, title: "Review the interface", cwd: "/demo/project",
            originator: nil, startedAt: now.addingTimeInterval(-120), lastActivityAt: now.addingTimeInterval(offset)
        ), completedAt: now.addingTimeInterval(offset))
    }

    private func withStore(_ run: (ConversationReadStore, UserDefaults) throws -> Void) throws {
        let suite = "ConversationAttentionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try run(ConversationReadStore(defaults: defaults), defaults)
    }

    private func content(completion: CompletedSession, receipts: [String: ConversationReadReceipt] = [:],
                         running: Bool = false, frontmost: Bool = false) throws -> ExpandedContent {
        let result = NotchPresentationReducer.reduce(NotchPresentationInput(
            now: now, isChatGPTFrontmost: frontmost,
            activeSessions: running ? [completion.session] : [], recentCompletions: [completion],
            usage: nil, isHovered: true, readReceipts: receipts
        ))
        guard case let .expanded(content) = result else { throw NSError(domain: "ExpectedExpanded", code: 1) }
        return content
    }

    func testCompletionStaysNewOnHoverAndAppActivationUntilSpecificLinkOpens() throws {
        try withStore { store, _ in
            let finished = completion()
            for frontmost in [false, true] {
                XCTAssertEqual(try content(completion: finished, receipts: store.receipts, frontmost: frontmost)
                    .conversations.first?.attention, .unread)
            }
            XCTAssertTrue(store.receipts.isEmpty)
            XCTAssertFalse(store.acknowledge(finished, threadLinkOpened: false))
            XCTAssertEqual(try content(completion: finished, receipts: store.receipts).conversations.first?.attention, .unread)
            XCTAssertTrue(store.acknowledge(finished, threadLinkOpened: true))
            XCTAssertEqual(try content(completion: finished, receipts: store.receipts).conversations.first?.attention, .viewed)
        }
    }

    func testReceiptSurvivesRestartButNewTurnAndRevisedCompletionBecomeNew() throws {
        try withStore { store, defaults in
            let finished = completion()
            store.acknowledge(finished, threadLinkOpened: true)
            let restarted = ConversationReadStore(defaults: defaults)
            XCTAssertEqual(try content(completion: finished, receipts: restarted.receipts).conversations.first?.attention, .viewed)
            for next in [completion(turn: "next", offset: 1), completion(turn: "next"), completion(offset: 1)] {
                XCTAssertEqual(try content(completion: next, receipts: restarted.receipts).conversations.first?.attention, .unread)
            }
            XCTAssertFalse(restarted.acknowledge(finished, threadLinkOpened: true))
        }
    }

    func testRunningAlwaysWinsOverOldReceiptAndDuplicateCompletion() throws {
        let finished = completion()
        let result = try content(completion: finished, receipts: ["thread": ConversationReadReceipt(finished)], running: true)
        XCTAssertEqual(result.conversations.count, 1)
        XCTAssertEqual(result.conversations.first?.attention, .running)
        XCTAssertEqual(result.headerConversation?.attention, .running)
        XCTAssertEqual(result.limitingRecentConversations(to: .none).conversations.count, 0)
    }

    func testReadReceiptsKeepCompactCompletionAndGroupUnreadBeforeViewed() throws {
        let finished = completion()
        var input = NotchPresentationInput(now: now, isChatGPTFrontmost: false,
                                          activeSessions: [], recentCompletions: [finished], usage: nil, isHovered: false)
        let before = NotchPresentationReducer.reduce(input)
        input.readReceipts = ["thread": ConversationReadReceipt(finished)]
        XCTAssertEqual(NotchPresentationReducer.reduce(input), before)
        let older = completion(thread: "older", offset: -100)
        let result = NotchPresentationReducer.reduce(NotchPresentationInput(
            now: now, isChatGPTFrontmost: false, activeSessions: [], recentCompletions: [finished, older],
            usage: nil, isHovered: true, readReceipts: input.readReceipts
        ))
        guard case let .expanded(content) = result else { return XCTFail("Expected expanded") }
        // CONVERSATION-ORDER-001 supersedes the chronological-only list order.
        XCTAssertEqual(content.conversations.map(\.threadID), ["older", "thread"])
        XCTAssertEqual(content.conversations.map(\.attention), [.unread, .viewed])
    }

    func testCorruptDataFallsBackSafelyAndStoredDataContainsOnlyReceiptMetadata() throws {
        try withStore { store, defaults in
            store.acknowledge(completion(), threadLinkOpened: true)
            let data = try XCTUnwrap(defaults.data(forKey: ConversationReadStore.storageKey))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
            XCTAssertEqual(Set(try XCTUnwrap(json["thread"]).keys), Set(["turnID", "completedAt"]))
            defaults.set(Data("broken".utf8), forKey: ConversationReadStore.storageKey)
            XCTAssertTrue(ConversationReadStore(defaults: defaults).receipts.isEmpty)
        }
    }

    func testReceiptStorageIsBoundedAndKeepsTheMostRecentlyOpenedOlderChat() throws {
        try withStore { store, defaults in
            for index in 0..<ConversationReadStore.maximumReceipts {
                store.acknowledge(completion(thread: "thread-\(index)", offset: Double(index)), threadLinkOpened: true)
            }
            let older = completion(thread: "old-chat", offset: -100_000)
            store.acknowledge(older, threadLinkOpened: true)
            XCTAssertEqual(store.receipts.count, ConversationReadStore.maximumReceipts)
            XCTAssertEqual(ConversationReadStore(defaults: defaults).receipts["old-chat"], ConversationReadReceipt(older))
        }
    }

    func testEveryLanguageNamesThreeDifferentStatesAndExplainsLocalAcknowledgement() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(Set(ConversationAttention.allCases.map { $0.label(language: language) }).count, 3)
            for attention in [ConversationAttention.unread, .viewed] {
                XCTAssertTrue(attention.hint(language: language).contains("CodexNotch"))
            }
        }
    }

    @MainActor
    func testProductionRowsKeepTheirHitAreasWithMotionOff() throws {
        _ = NSApplication.shared
        let now = self.now
        let finished = completion()
        let summaries = [
            ConversationSummary(session: finished.session, activity: .running(startedAt: finished.session.startedAt)),
            ConversationSummary(session: finished.session, activity: .completed(completedAt: now)),
            ConversationSummary(session: finished.session, activity: .completed(completedAt: now), isViewed: true)
        ]
        let titles = ["Обновить интерфейс приложения", "Проверить запуск и состояние чатов", "Собрать новую версию"]
        let root = VStack(spacing: 4) {
            ForEach(Array(summaries.enumerated()), id: \.offset) { index, summary in
                ConversationRowView(conversation: ConversationSummary(
                    session: SessionActivity(threadID: "preview-\(index)", turnID: "preview", title: titles[index],
                                             cwd: "/demo/codex-notch", originator: nil,
                                             startedAt: finished.session.startedAt, lastActivityAt: now),
                    activity: summary.activity, isViewed: summary.isViewed
                ), now: now, language: .russian, action: {})
            }
        }
        .padding(16)
        .frame(width: 420)
        .background(Color.black)
        .environment(\.notchMotionEnabled, false)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 160)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height, 160, accuracy: 1)
        if let output = ProcessInfo.processInfo.environment["NOTCH_CHAT_PREVIEW_PATH"] {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output))
        }
    }
}
