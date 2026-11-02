import Foundation
import XCTest
@testable import CodexNotch

final class IsolatedOutcomeReviewTests: XCTestCase {
    @MainActor
    func testColdHistoryLiveWorkReadAndFileReplayWithoutChangingPreferences() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "IsolatedOutcomeReviewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("ru", forKey: "appLanguage")
        defaults.set(0, forKey: "recentConversationCount")
        let file = root.appendingPathComponent("rollout.jsonl")
        let meta = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"thread\",\"source\":\"vscode\"}}\n"
        func turn(_ name: String, _ timestamp: String, finished: Bool) -> String {
            let start = "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"\(name)\"}}\n"
            let end = "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"\(name)\"}}\n"
            return start + (finished ? end : "")
        }
        let historical = meta + turn("old", "2020-01-01T00:00:00Z", finished: true)
        try Data(historical.utf8).write(to: file)
        let store = ActiveSessionStore()
        let signals = CompactCompletionStore(defaults: defaults)
        let monitor = RolloutActivityMonitor(rootURL: root, store: store)
        var noticeCount = 0
        monitor.onChange = { noticeCount += 1 }
        monitor.onNewCompletions = { signals.record($0) }
        monitor.start()
        defer { monitor.stop() }
        func waitFor(_ predicate: () async -> Bool) async throws {
            for _ in 0..<300 {
                if await predicate() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTFail("Expected snapshot was not observed")
        }
        func compact(_ snapshot: ActiveSessionStoreSnapshot, native: [String: NativeConversationReadReceipt] = [:]) -> NotchPresentationState {
            NotchPresentationReducer.reduce(NotchPresentationInput(now: Date(), isChatGPTFrontmost: false,
                activeSessions: snapshot.activeSessions, recentCompletions: snapshot.recentCompletions,
                usage: nil, isHovered: false, nativeReadReceipts: native, compactCompletionSignals: signals.signals))
        }
        try await waitFor { await store.snapshot().recentCompletions.first?.session.turnID == "old" }
        try await waitFor { noticeCount >= 1 }
        let historicalSnapshot = await store.snapshot()
        XCTAssertEqual(compact(historicalSnapshot), .quotaCompact(nil))
        XCTAssertTrue(signals.signals.isEmpty)
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = format.string(from: Date())
        let liveStart = historical + turn("new", timestamp, finished: false)
        try Data(liveStart.utf8).write(to: file)
        monitor.filesDidChange([file])
        try await waitFor { await store.snapshot().activeSessions.first?.turnID == "new" }
        try await waitFor { noticeCount >= 2 }
        let activeSnapshot = await store.snapshot()
        guard case .workingCompact = compact(activeSnapshot) else { return XCTFail("Expected running") }
        let liveFinished = historical + turn("new", timestamp, finished: true)
        try Data(liveFinished.utf8).write(to: file)
        monitor.filesDidChange([file])
        try await waitFor { signals.signals["thread"]?.turnID == "new" }
        try await waitFor { noticeCount >= 3 }
        let done = await store.snapshot()
        guard case .completedCompact = compact(done) else { return XCTFail("Expected completion") }
        let read = ["thread": NativeConversationReadReceipt(turnID: "new", isRead: true)]
        signals.removeViewed(local: [:], native: read)
        XCTAssertEqual(compact(done, native: read), .quotaCompact(nil))
        XCTAssertTrue(signals.signals.isEmpty)
        let beforeReplacement = noticeCount
        try Data((liveFinished + "\n").utf8).write(to: file, options: .atomic)
        monitor.filesDidChange([file])
        try await waitFor { noticeCount > beforeReplacement }
        XCTAssertTrue(signals.signals.isEmpty)
        let beforeRemoval = noticeCount
        try FileManager.default.removeItem(at: file)
        monitor.filesDidChange([file])
        try await waitFor { await store.snapshot().recentCompletions.isEmpty }
        try await waitFor { noticeCount > beforeRemoval }
        let beforeRestore = noticeCount
        try Data(liveFinished.utf8).write(to: file)
        monitor.filesDidChange([file])
        try await waitFor { await store.snapshot().recentCompletions.first?.session.turnID == "new" }
        try await waitFor { noticeCount > beforeRestore }
        XCTAssertTrue(signals.signals.isEmpty)
        let restoredSnapshot = await store.snapshot()
        XCTAssertEqual(compact(restoredSnapshot, native: read), .quotaCompact(nil))
        XCTAssertEqual(defaults.string(forKey: "appLanguage"), "ru")
        XCTAssertEqual(defaults.integer(forKey: "recentConversationCount"), 0)
    }
}
