import AppKit
import SwiftUI
import XCTest
@testable import CodexNotch

final class ConversationCategoryOrderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ id: String, offset: TimeInterval = 0) -> SessionActivity {
        SessionActivity(threadID: id, turnID: "turn-\(id)", title: id, cwd: "/demo",
                        originator: nil, startedAt: now.addingTimeInterval(-120),
                        lastActivityAt: now.addingTimeInterval(offset))
    }

    private func fixture(order: ConversationCategoryOrder = .defaultOrder, hovered: Bool = true)
        -> NotchPresentationInput {
        let unread = CompletedSession(session: session("new"), completedAt: now)
        let viewed = CompletedSession(session: session("viewed", offset: 10), completedAt: now.addingTimeInterval(10))
        return NotchPresentationInput(now: now, isChatGPTFrontmost: false,
                                      activeSessions: [session("running", offset: -10)],
                                      recentCompletions: [viewed, unread], usage: nil, isHovered: hovered,
                                      readReceipts: ["viewed": ConversationReadReceipt(viewed)],
                                      conversationCategoryOrder: order)
    }

    private func content(_ input: NotchPresentationInput, limit: RecentConversationLimit = .twenty)
        throws -> ExpandedContent {
        let state = NotchPresentationReducer.reduce(input).limitingRecentConversations(to: limit)
        guard case let .expanded(content) = state else { throw NSError(domain: "ExpectedExpanded", code: 1) }
        return content
    }

    func testDefaultGroupsRunningThenNewCompletionsThenViewedEvenWhenViewedIsNewer() throws {
        let result = try content(fixture())
        XCTAssertEqual(result.conversations.map(\.threadID), ["running", "new", "viewed"])
        XCTAssertEqual(result.conversations.map(\.attention), [.running, .unread, .viewed])
    }

    func testEveryCustomOrderIsAppliedAndKeepsRunningHeaderAndCompactPriority() throws {
        XCTAssertEqual(Set(ConversationCategoryOrder.allCases.map(\.rawValue)).count, 6)
        for order in ConversationCategoryOrder.allCases {
            let result = try content(fixture(order: order))
            XCTAssertEqual(result.conversations.map(\.attention), order.categories)
            XCTAssertEqual(result.headerConversation?.threadID, "running")
            let compact = NotchPresentationReducer.reduce(fixture(order: order, hovered: false))
            guard case let .workingCompact(primary, count, _) = compact else {
                return XCTFail("List order must never suppress compact running state")
            }
            XCTAssertEqual(primary.threadID, "running")
            XCTAssertEqual(count, 1)
        }
    }

    func testCategoryOrderingPrecedesBothTwentyCandidateCeilingAndEveryDisplayLimit() throws {
        var input = fixture(order: .unreadViewedRunning)
        input = NotchPresentationInput(now: input.now, isChatGPTFrontmost: false,
                                       activeSessions: (0..<25).map { session("running-\($0)", offset: Double($0)) },
                                       recentCompletions: input.recentCompletions, usage: nil, isHovered: true,
                                       readReceipts: input.readReceipts, conversationCategoryOrder: input.conversationCategoryOrder)
        for limit in RecentConversationLimit.allCases {
            let result = try content(input, limit: limit)
            XCTAssertEqual(result.conversations.count, limit.rawValue)
            XCTAssertEqual(result.sessions.count, 25)
            XCTAssertTrue(result.headerConversation?.activity.isRunning == true)
            if limit != .none { XCTAssertEqual(result.conversations.first?.threadID, "new") }
            if limit.rawValue > 1 { XCTAssertEqual(result.conversations[1].threadID, "viewed") }
            XCTAssertEqual(Set(result.conversations.map(\.threadID)).count, result.conversations.count)
        }
    }

    func testWithinEachCategoryUsesNewestTimeAndStableThreadIdentityForTiesWithoutDuplicates() throws {
        let older = CompletedSession(session: session("old", offset: 50), completedAt: now.addingTimeInterval(-10))
        let newest = CompletedSession(session: session("newest", offset: -50), completedAt: now.addingTimeInterval(10))
        let tieA = CompletedSession(session: session("tie-a"), completedAt: now)
        let tieB = CompletedSession(session: session("tie-b"), completedAt: now)
        let active = session("active", offset: -30)
        let input = NotchPresentationInput(now: now, isChatGPTFrontmost: false,
                                          activeSessions: [active, session("active-newer"), active],
                                          recentCompletions: [older, tieB, tieA, newest, older,
                                                              CompletedSession(session: active, completedAt: now)],
                                          usage: nil, isHovered: true)
        for source in [input.recentCompletions, Array(input.recentCompletions.reversed())] {
            let reorderedInput = NotchPresentationInput(now: input.now, isChatGPTFrontmost: false,
                                                       activeSessions: Array(input.activeSessions.reversed()),
                                                       recentCompletions: source, usage: nil, isHovered: true)
            let rows = try content(reorderedInput).conversations
            XCTAssertEqual(rows.map(\.threadID), ["active-newer", "active", "newest", "tie-a", "tie-b", "old"])
            XCTAssertEqual(rows.first(where: { $0.threadID == "active" })?.attention, .running)
        }
    }

    func testNewestCompletedTurnWinsDeduplicationAndEachCategoryKeepsTimeOrder() throws {
        let old = CompletedSession(session: session("same", offset: -40), completedAt: now.addingTimeInterval(-40))
        let latest = CompletedSession(session: session("same", offset: 20), completedAt: now.addingTimeInterval(20))
        let unread = CompletedSession(session: session("unread", offset: -10), completedAt: now.addingTimeInterval(-10))
        let viewedOld = CompletedSession(session: session("viewed-old", offset: -50), completedAt: now.addingTimeInterval(-50))
        let viewedNew = CompletedSession(session: session("viewed-new", offset: 50), completedAt: now.addingTimeInterval(50))
        let expectedByCategory: [(ConversationAttention, [String])] = [
            (.running, ["running-new", "running-old"]), (.unread, ["same", "unread"]),
            (.viewed, ["viewed-new", "viewed-old"])
        ]
        for order in ConversationCategoryOrder.allCases {
            let input = NotchPresentationInput(now: now, isChatGPTFrontmost: false,
                                              activeSessions: [session("running-old", offset: -30), session("running-new")],
                                              recentCompletions: [old, viewedOld, unread, viewedNew, latest],
                                              usage: nil, isHovered: true,
                                              readReceipts: ["same": ConversationReadReceipt(old),
                                                             "viewed-old": ConversationReadReceipt(viewedOld),
                                                             "viewed-new": ConversationReadReceipt(viewedNew)],
                                              conversationCategoryOrder: order)
            let rows = try content(input).conversations
            let expectedIDs = order.categories.flatMap { category in
                expectedByCategory.first { $0.0 == category }!.1
            }
            XCTAssertEqual(rows.map(\.threadID), expectedIDs)
            XCTAssertEqual(rows.first { $0.threadID == "same" }?.activity, .completed(completedAt: latest.completedAt))
            XCTAssertEqual(rows.first { $0.threadID == "same" }?.attention, .unread,
                           "An old receipt must not classify the newer completion as viewed")
        }
    }

    func testSettingsMovesReachAllPermutationsAndDoNotWrapAtEdges() {
        var visited = Set<String>()
        var pending = [ConversationCategoryOrder.defaultOrder]
        while let order = pending.popLast() {
            guard visited.insert(order.rawValue).inserted else { continue }
            for category in order.categories {
                pending += [order.moving(category, by: -1), order.moving(category, by: 1)]
            }
            XCTAssertEqual(order.moving(order.categories[0], by: -1), order)
            XCTAssertEqual(order.moving(order.categories[2], by: 1), order)
            XCTAssertEqual(order.moving(order.categories[0], by: 10), order)
        }
        XCTAssertEqual(visited, Set(ConversationCategoryOrder.allCases.map(\.rawValue)))
    }

    func testPersistedAndLivePreferencesApplyOrderWithoutChangingOtherPreferences() throws {
        let suite = "ConversationCategoryOrderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(20, forKey: RecentConversationLimit.storageKey)
        defaults.set("ru", forKey: AppLanguage.storageKey)
        defaults.set(false, forKey: AppAnimationPreference.storageKey)
        let initial = NotchRuntimePreferences.read(from: defaults)
        XCTAssertEqual(initial.conversationCategoryOrder, .defaultOrder)
        for order in ConversationCategoryOrder.allCases {
            defaults.set(order.rawValue, forKey: ConversationCategoryOrder.storageKey)
            let live = NotchRuntimePreferences.read(from: defaults)
            var expected = initial
            expected.conversationCategoryOrder = order
            XCTAssertEqual(live, expected, "Only category order should change")
            var input = fixture()
            input.conversationCategoryOrder = live.conversationCategoryOrder
            XCTAssertEqual(try content(input, limit: live.recentConversationLimit).conversations.map(\.attention), order.categories)
            let restarted = try XCTUnwrap(UserDefaults(suiteName: suite))
            XCTAssertEqual(NotchRuntimePreferences.read(from: restarted), live)
        }
    }

    func testMissingMalformedAndWrongTypePreferencesUseSafeDefault() throws {
        let suite = "ConversationCategoryOrderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for invalid: Any in ["", "viewed", "running,unread,unread", "future-format", 42, ["running", "unread", "viewed"], Data([0])] {
            defaults.set(invalid, forKey: ConversationCategoryOrder.storageKey)
            XCTAssertEqual(NotchRuntimePreferences.read(from: defaults).conversationCategoryOrder, .defaultOrder)
        }
        defaults.removeObject(forKey: ConversationCategoryOrder.storageKey)
        XCTAssertEqual(NotchRuntimePreferences.read(from: defaults).conversationCategoryOrder, .defaultOrder)
    }

    func testZeroHidesOnlyTheListAndCompletionCompactIgnoresEveryOrder() throws {
        for order in ConversationCategoryOrder.allCases {
            let result = try content(fixture(order: order), limit: .none)
            XCTAssertTrue(result.conversations.isEmpty)
            XCTAssertEqual(result.headerConversation?.threadID, "running")
            var input = fixture(order: order, hovered: false)
            input = NotchPresentationInput(now: now, isChatGPTFrontmost: true, activeSessions: [],
                                           recentCompletions: input.recentCompletions, usage: nil, isHovered: false,
                                           readReceipts: input.readReceipts,
                                           compactCompletionSignals: ["new": ConversationReadReceipt(input.recentCompletions[1])],
                                           conversationCategoryOrder: order)
            XCTAssertEqual(NotchPresentationReducer.reduce(input), .completedCompact(session("new"), usage: nil))
        }
    }

    @MainActor
    private func settle(_ host: NSView) {
        for _ in 0..<4 {
            while let event = NSApp.nextEvent(matching: .any, until: .distantPast,
                                             inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            NSApp.updateWindows()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
    }

    private struct StoredControl: View {
        @AppStorage(ConversationCategoryOrder.storageKey) private var raw = ConversationCategoryOrder.defaultOrder.rawValue
        var onChange: (ConversationCategoryOrder) -> Void
        var body: some View {
            ConversationCategoryOrderControl(order: Binding(
                get: { ConversationCategoryOrder.fromStoredValue(raw) },
                set: { raw = $0.rawValue }
            ), language: .english)
            .padding(16).frame(width: 480)
            .onChange(of: raw) { _, value in onChange(ConversationCategoryOrder.fromStoredValue(value)) }
        }
    }

    @MainActor
    func testLiveAppStorageSettingUpdatesVisibleControlAndPresentationWithoutRestart() throws {
        _ = NSApplication.shared
        let suite = "ConversationCategoryOrderTests.UI.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var observed: [ConversationCategoryOrder] = []
        let host = NSHostingView(rootView: StoredControl(onChange: { observed.append($0) }).defaultAppStorage(defaults))
        host.sizingOptions = []
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        settle(host)
        let initial = NotchRuntimePreferences.read(from: defaults)
        defaults.set(ConversationCategoryOrder.unreadRunningViewed.rawValue, forKey: ConversationCategoryOrder.storageKey)
        settle(host)
        XCTAssertEqual(observed.last, .unreadRunningViewed, "The mounted settings control must observe the preference live")
        let live = NotchRuntimePreferences.read(from: defaults)
        XCTAssertNotEqual(live, initial, "The existing preference observer must see the change")
        XCTAssertEqual(live.conversationCategoryOrder, .unreadRunningViewed)
        var input = fixture()
        input.conversationCategoryOrder = live.conversationCategoryOrder
        XCTAssertEqual(try content(input).conversations.map(\.threadID), ["new", "running", "viewed"])
    }

    @MainActor
    func testLocalizedControlUsesCompactThreeRowsAndHasDistinctCategoryNames() throws {
        _ = NSApplication.shared
        for language in AppLanguage.allCases {
            let titles = ConversationCategoryOrder.defaultOrder.categories.map {
                ConversationCategoryOrder.title(for: $0, language: language)
            }
            XCTAssertEqual(Set(titles).count, 3)
            let host = NSHostingView(rootView: ConversationCategoryOrderControl(order: .constant(.defaultOrder), language: language)
                .padding(16).frame(width: 480))
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            window.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            settle(host)
            defer { window.orderOut(nil); window.contentView = nil }
            XCTAssertLessThan(host.fittingSize.height, 160, "Category controls must fit the existing Settings window")
            if let folder = ProcessInfo.processInfo.environment["NOTCH_ORDER_PREVIEW_DIR"] {
                let bitmap = try hostedViewSnapshot(ConversationCategoryOrderControl(order: .constant(.defaultOrder), language: language)
                    .padding(16).frame(width: 480).background(Color(nsColor: .windowBackgroundColor)))
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: folder).appendingPathComponent("order-\(language.rawValue).png"))
            }
        }
        XCTAssertEqual(ConversationCategoryOrder.title(for: .unread, language: .russian), "Завершённые (новые)")
        XCTAssertEqual(ConversationCategoryOrder.title(for: .viewed, language: .russian), "Прочитанные")
    }
}
