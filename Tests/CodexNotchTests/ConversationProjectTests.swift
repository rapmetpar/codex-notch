import AppKit
import SwiftUI
import SQLite3
import XCTest
@testable import CodexNotch

final class ConversationProjectTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func session(_ id: String, cwd: String? = "/sample/A", time: TimeInterval = 0) -> SessionActivity {
        SessionActivity(threadID: id, turnID: "turn-\(id)", title: "Synthetic \(id)", cwd: cwd,
                        originator: nil, startedAt: now, lastActivityAt: now.addingTimeInterval(time))
    }
    func content(_ input: NotchPresentationInput, limit: RecentConversationLimit = .twenty) throws -> ExpandedContent {
        guard case let .expanded(value) = NotchPresentationReducer.reduce(input).limitingRecentConversations(to: limit)
        else { throw NSError(domain: "ExpectedExpanded", code: 1) }
        return value
    }
    func input() -> NotchPresentationInput {
        let completions = ["A", "B"].flatMap { project in
            [CompletedSession(session: session("\(project)-new", cwd: "/sample/\(project)"), completedAt: now),
             CompletedSession(session: session("\(project)-viewed", cwd: "/sample/\(project)"), completedAt: now)]
        }
        return NotchPresentationInput(now: now, isChatGPTFrontmost: false,
            activeSessions: [session("A-running"), session("B-running", cwd: "/sample/B")],
            recentCompletions: completions, usage: nil, isHovered: true,
            nativeReadReceipts: ["A-viewed": NativeConversationReadReceipt(turnID: "turn-A-viewed"),
                                 "B-viewed": NativeConversationReadReceipt(turnID: "turn-B-viewed")])
    }

    func testCanonicalFallbackSameNameDistinctPathsAndOpaqueNativeIdentity() throws {
        let a = ConversationProject.fallback(cwd: "/sample/one/demo")
        let b = ConversationProject.fallback(cwd: "/sample/two/demo")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.name, b.name)
        XCTAssertEqual(a, .fallback(cwd: "/sample/one/./demo/../demo/"))
        XCTAssertFalse(a.id.contains("sample"))
        XCTAssertEqual(ConversationProject.fallback(cwd: nil), .unassigned)
        XCTAssertEqual(ConversationProject.fallback(cwd: "relative"), .unassigned)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let alias = root.appendingPathComponent("alias")
        let original = root.appendingPathComponent("original")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        XCTAssertEqual(ConversationProject.fallback(cwd: alias.path), .fallback(cwd: original.path))
        let native = ConversationProject.native(id: "stable-project", name: "Old", cwd: "/old")
        XCTAssertEqual(native.id, ConversationProject.native(id: "stable-project", name: "Renamed", cwd: "/new").id)
        XCTAssertNotEqual(native.id, ConversationProject.native(id: "different", name: "Old", cwd: "/old").id)
        XCTAssertFalse(native.id.contains("stable-project"))
    }

    func testSameNameHeadingsAreDistinctAndUnassignedIsLocalizedWithoutLosingChats() throws {
        var value = input()
        value = value.replacing(activeSessions: [session("one", cwd: "/sample/one/demo"), session("two", cwd: "/sample/two/demo"), session("unknown", cwd: nil)])
        value = value.replacing(recentCompletions: [])
        let sections = try content(value).projectSections
        XCTAssertEqual(Set(sections.map(\.id)).count, 3)
        XCTAssertEqual(Set(sections.map { $0.title(language: .english) }).count, 3)
        XCTAssertEqual(sections.flatMap(\.conversations).count, 3)
        XCTAssertEqual(sections.first { $0.id == "unassigned" }?.title(language: .russian), "Без проекта")
    }

    func testEveryOuterAndInnerPermutationSortsBeforeBothLimitsAndKeepsCompactRunning() throws {
        let a = ConversationProject.fallback(cwd: "/sample/A").id
        let b = ConversationProject.fallback(cwd: "/sample/B").id
        let c = ConversationProject.fallback(cwd: "/sample/C").id
        let permutations = [[a,b,c], [a,c,b], [b,a,c], [b,c,a], [c,a,b], [c,b,a]]
        for projectIDs in permutations {
            for categories in ConversationCategoryOrder.allCases {
                var value = input()
                value = value.replacing(activeSessions: value.activeSessions + [session("C-running", cwd: "/sample/C")],
                    recentCompletions: value.recentCompletions + [
                        CompletedSession(session: session("C-new", cwd: "/sample/C"), completedAt: now),
                        CompletedSession(session: session("C-viewed", cwd: "/sample/C"), completedAt: now)])
                value.nativeReadReceipts["C-viewed"] = NativeConversationReadReceipt(turnID: "turn-C-viewed")
                value.conversationProjectOrder = ConversationProjectOrder(ids: projectIDs)
                value.conversationCategoryOrder = categories
                let rows = try content(value).conversations
                XCTAssertEqual(rows.map(\.project.id), projectIDs.flatMap { Array(repeating: $0, count: 3) })
                for group in try content(value).projectSections {
                    XCTAssertEqual(group.conversations.map(\.attention), categories.categories)
                }
                for limit in RecentConversationLimit.allCases {
                    let bounded = try content(value, limit: limit)
                    XCTAssertEqual(bounded.conversations.map(\.threadID), Array(rows.prefix(limit.rawValue)).map(\.threadID))
                    XCTAssertEqual(bounded.allProjectIDs, projectIDs)
                    if limit == .none { XCTAssertTrue(bounded.projectSections.isEmpty) }
                }
                value = value.replacing(isHovered: false)
                guard case .workingCompact = NotchPresentationReducer.reduce(value) else {
                    return XCTFail("Project and category order cannot change compact running priority")
                }
            }
        }
        var value = input()
        value = value.replacing(activeSessions: value.activeSessions + (0..<30).map { session("extra-\($0)", time: Double($0)) })
        value.conversationProjectOrder = ConversationProjectOrder(ids: [b, a])
        XCTAssertEqual(try content(value).conversations.first?.project.id, b,
                       "A preferred project must survive the global candidate ceiling")
        XCTAssertEqual(try content(value).conversations.count, 20)
    }

    func testProjectMetadataOverridesCWDAndNativeReadAndDedupRemainExact() throws {
        var value = input()
        value.threadProjects = ["A-running": NativeThreadProject(id: "B-native", name: "Renamed")]
        value = value.replacing(recentCompletions: value.recentCompletions + [CompletedSession(session: session("A-running"), completedAt: now),
                                    CompletedSession(session: session("A-new", time: -20), completedAt: now.addingTimeInterval(-20))])
        let result = try content(value)
        XCTAssertEqual(result.conversations.filter { $0.threadID == "A-running" }.count, 1)
        let running = try XCTUnwrap(result.conversations.first { $0.threadID == "A-running" })
        XCTAssertEqual(running.project.name, "Renamed")
        XCTAssertEqual(running.attention, .running)
        XCTAssertEqual(result.conversations.first { $0.threadID == "A-viewed" }?.attention, .viewed)
        XCTAssertEqual(result.conversations.first { $0.threadID == "A-new" }?.activity, .completed(completedAt: now))
        value.threadProjects = [:]
        XCTAssertEqual(try content(value).conversations.first { $0.threadID == "A-running" }?.project,
                       ConversationProject.fallback(cwd: "/sample/A"))
    }

    func testProjectOrderPreservesChronologyAndThreadTiesWithinEachCategory() throws {
        var value = input()
        value = value.replacing(activeSessions: [session("tie-z"), session("tie-a"), session("new", time: 10)])
        value = value.replacing(recentCompletions: [])
        for order in ConversationCategoryOrder.allCases {
            value.conversationCategoryOrder = order
            XCTAssertEqual(try content(value).conversations.map(\.threadID), ["new", "tie-a", "tie-z"])
            value = value.replacing(activeSessions: Array(value.activeSessions.reversed()))
        }
    }

    @MainActor
    func testActualDropRouteAndKeyboardMoveApplyLivePersistAcrossRestartAndRejectBadPayloads() throws {
        let suite = "ConversationProjectTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(20, forKey: RecentConversationLimit.storageKey)
        let store = ConversationProjectOrderStore(defaults: defaults)
        var value = input()
        let initial = try content(value)
        let ids = initial.allProjectIDs
        store.discover(ids)
        let model = NotchViewModel(state: .expanded(initial), now: now)
        model.onProjectOrderChange = { next in
            XCTAssertTrue(store.prioritize(next))
            value.conversationProjectOrder = store.order
            _ = model.update(state: .expanded(try! self.content(value)), now: self.now, animationsEnabled: false)
        }
        // Exactly the closure used by .dropDestination calls this production route.
        XCTAssertTrue(model.dropProjects([ProjectDragToken(id: ids[0])], onto: ids[1]))
        XCTAssertEqual(try content(value).projectSections.map(\.id), Array(ids.reversed()))
        XCTAssertEqual(ConversationProjectOrder.read(from: try XCTUnwrap(UserDefaults(suiteName: suite))), store.order)
        XCTAssertEqual(NotchRuntimePreferences.read(from: defaults).conversationProjectOrder, store.order)
        XCTAssertEqual(defaults.integer(forKey: RecentConversationLimit.storageKey), 20)
        model.moveProject(ids[0], by: -1)
        XCTAssertEqual(try content(value).allProjectIDs, ids)
        for tokens in [[], [ProjectDragToken(id: "/private/path")], [ProjectDragToken(id: ids[0]), ProjectDragToken(id: ids[0])],
                       [ProjectDragToken(id: ConversationProject.fallback(cwd: "/missing").id)]] {
            XCTAssertFalse(model.dropProjects(tokens, onto: ids[1]))
        }
        XCTAssertFalse(model.dropProjects([ProjectDragToken(id: ids[0])], onto: "invalid"))
        XCTAssertFalse(model.dropProjects([ProjectDragToken(id: ids[0])], onto: ids[0]))
        XCTAssertFalse(try String(data: JSONEncoder().encode(ProjectDragToken(id: ids[0])), encoding: .utf8)!.contains("sample"))
        let added = ConversationProject.fallback(cwd: "/new/project").id
        store.discover([added] + ids)
        XCTAssertEqual(store.order.ids, ids + [added])
        // Temporary disappearance, then reappearance keeps its identity and no chat is removed.
        let renamed = NativeThreadProject(id: "same", name: "New name")
        value.threadProjects["A-new"] = renamed
        XCTAssertEqual(try content(value).conversations.count, 6)
        store.discover(ids)
        XCTAssertEqual(store.order.ids, ids + [added])
    }

    @MainActor
    func testRealItemProviderTransferReachesProductionDropAndDoesNotExportAFilePath() async throws {
        let value = try content(input())
        let ids = value.allProjectIDs
        let model = NotchViewModel(state: .expanded(value), now: now)
        var order: [String] = []
        model.onProjectOrderChange = { order = $0 }
        func decode(_ provider: NSItemProvider) async throws -> ProjectDragToken {
            try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadTransferable(type: ProjectDragToken.self) { result in continuation.resume(with: result) }
            }
        }
        let provider = NSItemProvider()
        provider.register(ProjectDragToken(id: ids[0]))
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains("app.codexnotch.project-order"))
        XCTAssertFalse(provider.registeredTypeIdentifiers.contains("public.file-url"))
        let token = try await decode(provider)
        XCTAssertEqual(token, ProjectDragToken(id: ids[0]))
        XCTAssertTrue(model.dropProjects([token], onto: ids[1]))
        XCTAssertEqual(order, Array(ids.reversed()))
        let invalid = NSItemProvider()
        invalid.register(ProjectDragToken(id: "/synthetic/private/path"))
        let invalidToken = try await decode(invalid)
        XCTAssertFalse(model.dropProjects([invalidToken], onto: ids[1]))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("Resources/Info.plist")), format: nil) as! [String: Any]
        let declarations = try XCTUnwrap(plist["UTExportedTypeDeclarations"] as? [[String: Any]])
        let declaration = try XCTUnwrap(declarations.first { ($0["UTTypeIdentifier"] as? String) == "app.codexnotch.project-order" })
        XCTAssertEqual(declaration["UTTypeConformsTo"] as? [String], ["public.data"])
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.david.codexnotch")
    }

    func testMalformedDuplicateAndWrongTypeOrdersFailClosed() throws {
        let suite = "ConversationProjectTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = ConversationProject.fallback(cwd: "/demo").id
        for invalid: Any in ["invalid", 42, [id, id], [id, "garbage"], [42], Data([1])] {
            defaults.set(invalid, forKey: ConversationProjectOrder.storageKey)
            XCTAssertEqual(ConversationProjectOrder.read(from: defaults).ids, [])
        }
        let store = ConversationProjectOrderStore(defaults: defaults)
        XCTAssertFalse(store.prioritize([id, id]))
        XCTAssertFalse(store.prioritize(["/private/path"]))
    }
}

// Test fixture copies leave the production input's immutable source fields intact.
extension NotchPresentationInput {
    func replacing(activeSessions: [SessionActivity]? = nil, recentCompletions: [CompletedSession]? = nil,
                   isHovered: Bool? = nil) -> Self {
        Self(now: now, isChatGPTFrontmost: isChatGPTFrontmost,
             activeSessions: activeSessions ?? self.activeSessions,
             recentCompletions: recentCompletions ?? self.recentCompletions, usage: usage,
             isHovered: isHovered ?? self.isHovered, readReceipts: readReceipts,
             nativeReadReceipts: nativeReadReceipts, conversationCategoryOrder: conversationCategoryOrder,
             threadProjects: threadProjects, conversationProjectOrder: conversationProjectOrder)
    }
}
