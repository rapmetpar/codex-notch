import XCTest
@testable import CodexNotch

final class NativeThreadSnapshotTests: XCTestCase {
    func testHistoricalReadNewCompletionAndNativeTransition() {
        let t = Date(timeIntervalSince1970: 100)
        let a = ConversationReadReceipt(turnID: "a", completedAt: t)
        let b = ConversationReadReceipt(turnID: "b", completedAt: t.addingTimeInterval(10))
        var policy = NativeThreadReadPolicy(startedAt: t.addingTimeInterval(5))
        policy.update(["thread": a])
        XCTAssertEqual(policy.apply(snapshot: .init(status: ["thread": true], fingerprint: "one", modifiedAt: t)), ["thread": NativeConversationReadReceipt(turnID: "a")])
        policy.update(["thread": b])
        XCTAssertTrue(policy.apply(snapshot: .init(status: ["thread": true], fingerprint: "one", modifiedAt: t)).isEmpty)
        let new = policy.apply(snapshot: .init(status: ["thread": false], fingerprint: "two", modifiedAt: t.addingTimeInterval(11)))
        XCTAssertEqual(new["thread"], NativeConversationReadReceipt(turnID: "b", isRead: false))
        let viewed = policy.apply(snapshot: .init(status: ["thread": true], fingerprint: "three", modifiedAt: t.addingTimeInterval(12)))
        XCTAssertEqual(viewed["thread"], NativeConversationReadReceipt(turnID: "b"))
        XCTAssertTrue(policy.apply(snapshot: nil).isEmpty)
    }
}

import CryptoKit
import SQLite3

extension NativeThreadSnapshotTests {
    func testScopedSnapshotReadsKnownThreadsAndHandlesWALReplacementAndLoss() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let dbURL = home.appendingPathComponent("state_5.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE threads(id TEXT, creator_account_id TEXT, creator_user_id TEXT); INSERT INTO threads VALUES('known','account','user'),('foreign','different','user');", nil, nil, nil), SQLITE_OK)
        let bytes = try JSONSerialization.data(withJSONObject: ["chatgpt", "account", "user"], options: [.withoutEscapingSlashes])
        let identity = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let stateURL = home.appendingPathComponent(".codex-global-state.json")
        func write(_ unread: [String], version: Int = 1, host: String = "local:host") throws {
            let state: [String: Any] = ["electron-thread-read-state-v1": ["version": version,
                "unreadByIdentity": [identity: [host: unread]],
                "legacyMigration": ["identityKey": identity, "adoptedHostIds": ["local": host]]]]
            try JSONSerialization.data(withJSONObject: state).write(to: stateURL, options: .atomic)
        }
        try write([])
        var rootWithUnknown = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any])
        rootWithUnknown["unrelated"] = ["arbitrary": [1, 2, 3]]
        try JSONSerialization.data(withJSONObject: rootWithUnknown).write(to: stateURL, options: .atomic)
        let reader = NativeThreadReadSnapshotReader(codexHomeURL: home)
        let ids = ["known", "foreign", "missing"]
        XCTAssertEqual(reader.snapshot(for: ids)?.status, ["known": true])
        try write(["known"])
        XCTAssertEqual(reader.snapshot(for: ids)?.status, ["known": false])
        try write([], version: 2)
        XCTAssertNil(reader.snapshot(for: ids))
        try write([])
        let validBytes = try Data(contentsOf: stateURL)
        func mutate(_ edit: (inout [String: Any]) -> Void) throws {
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: validBytes) as? [String: Any])
            var state = try XCTUnwrap(root["electron-thread-read-state-v1"] as? [String: Any])
            edit(&state)
            root["electron-thread-read-state-v1"] = state
            try JSONSerialization.data(withJSONObject: root).write(to: stateURL, options: .atomic)
        }
        try mutate { state in
            var identities = state["unreadByIdentity"] as! [String: Any]
            identities["other-identity"] = ["local:host": []]
            state["unreadByIdentity"] = identities
        }
        XCTAssertNil(reader.snapshot(for: ids))
        try mutate { state in
            var migration = state["legacyMigration"] as! [String: Any]
            migration["cleared"] = true
            state["legacyMigration"] = migration
        }
        XCTAssertNil(reader.snapshot(for: ids))
        try mutate { state in
            var identities = state["unreadByIdentity"] as! [String: Any]
            identities[identity] = ["local:host": [], "local:other": []]
            state["unreadByIdentity"] = identities
        }
        XCTAssertNil(reader.snapshot(for: ids))
        try mutate { state in state["unreadByIdentity"] = [identity: ["local:host": [42]]] }
        XCTAssertNil(reader.snapshot(for: ids))
        try write([])
        XCTAssertEqual(sqlite3_exec(db, "DELETE FROM threads WHERE id='known'", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(reader.snapshot(for: ids)?.status, [:])
        XCTAssertEqual(sqlite3_close(db), SQLITE_OK)
        db = nil
        let replacementURL = home.appendingPathComponent("replacement.sqlite")
        var replacement: OpaquePointer?
        XCTAssertEqual(sqlite3_open(replacementURL.path, &replacement), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(replacement, "CREATE TABLE threads(id TEXT, creator_account_id TEXT, creator_user_id TEXT); INSERT INTO threads VALUES('known','account','user');", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_close(replacement), SQLITE_OK)
        XCTAssertEqual(rename(replacementURL.path, dbURL.path), 0)
        XCTAssertEqual(reader.snapshot(for: ids)?.status, ["known": true])
        try FileManager.default.removeItem(at: stateURL)
        XCTAssertNil(reader.snapshot(for: ids))
    }

    func testNewCompletionDoesNotReuseUnchangedReadSnapshot() {
        let start = Date(timeIntervalSince1970: 100)
        var policy = NativeThreadReadPolicy(startedAt: start)
        let a = ConversationReadReceipt(turnID: "a", completedAt: start.addingTimeInterval(-1))
        let b = ConversationReadReceipt(turnID: "b", completedAt: start.addingTimeInterval(1))
        policy.update(["thread": a])
        let old = NativeThreadReadSnapshot(status: ["thread": true], fingerprint: "old", modifiedAt: start)
        XCTAssertNotNil(policy.apply(snapshot: old)["thread"])
        policy.update(["thread": b])
        XCTAssertNil(policy.apply(snapshot: old)["thread"])
        let laterSame = NativeThreadReadSnapshot(status: ["thread": true], fingerprint: "old", modifiedAt: start.addingTimeInterval(30))
        XCTAssertNil(policy.apply(snapshot: laterSame)["thread"])
        let current = NativeThreadReadSnapshot(status: ["thread": false], fingerprint: "new", modifiedAt: start.addingTimeInterval(31))
        XCTAssertEqual(policy.apply(snapshot: current)["thread"]?.isRead, false)
    }
}

extension NativeThreadSnapshotTests {
    func testSnapshotDrivesActualPresentationAndRunningPriority() {
        let now = Date(timeIntervalSince1970: 1000)
        let session = SessionActivity(threadID: "thread", turnID: "turn-a", title: nil, cwd: nil,
                                      originator: nil, startedAt: now.addingTimeInterval(-20), lastActivityAt: now)
        let finished = CompletedSession(session: session, completedAt: now)
        var policy = NativeThreadReadPolicy(startedAt: now.addingTimeInterval(1))
        policy.update(["thread": ConversationReadReceipt(finished)])
        func attention(_ native: [String: NativeConversationReadReceipt], running: Bool = false) -> ConversationAttention? {
            let input = NotchPresentationInput(now: now, isChatGPTFrontmost: false,
                activeSessions: running ? [session] : [], recentCompletions: [finished], usage: nil,
                isHovered: true, nativeReadReceipts: native)
            guard case let .expanded(content) = NotchPresentationReducer.reduce(input) else { return nil }
            return content.conversations.first?.attention
        }
        let unread = policy.apply(snapshot: .init(status: ["thread": false], fingerprint: "unread", modifiedAt: now))
        XCTAssertEqual(attention(unread), .unread)
        let read = policy.apply(snapshot: .init(status: ["thread": true], fingerprint: "read", modifiedAt: now))
        XCTAssertEqual(attention(read), .viewed)
        XCTAssertEqual(attention(read, running: true), .running)
        XCTAssertEqual(attention(policy.apply(snapshot: nil)), .unread)
    }
}

extension NativeThreadSnapshotTests {
    func testFirstSnapshotAfterNewCompletionIsOnlyABaseline() {
        let start = Date(timeIntervalSince1970: 10)
        var policy = NativeThreadReadPolicy(startedAt: start)
        policy.update(["thread": ConversationReadReceipt(turnID: "new", completedAt: start.addingTimeInterval(1))])
        let snapshot = NativeThreadReadSnapshot(status: ["thread": true], fingerprint: "first", modifiedAt: start.addingTimeInterval(2))
        XCTAssertNil(policy.apply(snapshot: snapshot)["thread"])
        XCTAssertNil(policy.apply(snapshot: snapshot)["thread"])
        let changed = NativeThreadReadSnapshot(status: ["thread": false], fingerprint: "second", modifiedAt: start.addingTimeInterval(3))
        XCTAssertEqual(policy.apply(snapshot: changed)["thread"]?.isRead, false)
    }
}

extension NativeThreadSnapshotTests {
    func testOpenNativeChatCanBecomeViewedWithoutUnreadListChange() {
        let start = Date(timeIntervalSince1970: 100)
        var policy = NativeThreadReadPolicy(startedAt: start)
        let a = ConversationReadReceipt(turnID: "a", completedAt: start.addingTimeInterval(-1))
        let b = ConversationReadReceipt(turnID: "b", completedAt: start.addingTimeInterval(1))
        policy.update(["thread": a])
        let before = NativeThreadReadSnapshot(status: ["thread": true], fingerprint: "unchanged", modifiedAt: start,
                                              updatedAt: ["thread": start.addingTimeInterval(-1)])
        XCTAssertEqual(policy.apply(snapshot: before)["thread"]?.turnID, "a")
        policy.update(["thread": b])
        XCTAssertNil(policy.apply(snapshot: before)["thread"])
        let after = NativeThreadReadSnapshot(status: ["thread": true], fingerprint: "unchanged", modifiedAt: start,
                                             updatedAt: ["thread": start.addingTimeInterval(1)])
        XCTAssertEqual(policy.apply(snapshot: after)["thread"], NativeConversationReadReceipt(turnID: "b"))
    }

    func testIdentityOrHostScopeChangeDoesNotReuseTrust() {
        let start = Date(timeIntervalSince1970: 100)
        var policy = NativeThreadReadPolicy(startedAt: start)
        policy.update(["thread": ConversationReadReceipt(turnID: "b", completedAt: start.addingTimeInterval(1))])
        let first = NativeThreadReadSnapshot(status: ["thread": true], fingerprint: "same", modifiedAt: start,
                                             updatedAt: ["thread": start.addingTimeInterval(1)], scope: "one")
        XCTAssertNotNil(policy.apply(snapshot: first)["thread"])
        let second = NativeThreadReadSnapshot(status: ["thread": true], fingerprint: "same", modifiedAt: start, scope: "two")
        XCTAssertNil(policy.apply(snapshot: second)["thread"])
    }
}

extension NativeThreadSnapshotTests {
    private final class MutableSnapshotReader: NativeThreadReadSnapshotReading {
        private let lock = NSLock()
        private var current: NativeThreadReadSnapshot?
        func set(_ snapshot: NativeThreadReadSnapshot?) { lock.lock(); current = snapshot; lock.unlock() }
        func snapshot(for threadIDs: [String]) -> NativeThreadReadSnapshot? {
            lock.lock(); defer { lock.unlock() }; return current
        }
    }

    @MainActor
    func testMonitorPublishesNativeChangesAndClearsUnavailableSource() {
        let reader = MutableSnapshotReader()
        let past = Date().addingTimeInterval(-20)
        let session = SessionActivity(threadID: "thread", turnID: "turn", title: nil, cwd: nil,
                                      originator: nil, startedAt: past, lastActivityAt: past)
        let completion = CompletedSession(session: session, completedAt: past)
        reader.set(.init(status: ["thread": false], fingerprint: "unread", modifiedAt: past))
        let monitor = NativeConversationReadMonitor(snapshotReader: reader, refreshInterval: 0.02)
        let observed = expectation(description: "native unread, read and source loss")
        var phase = 0
        monitor.onChange = {
            switch phase {
            case 0:
                XCTAssertEqual(monitor.receipts["thread"]?.isRead, false)
                phase = 1
                reader.set(.init(status: ["thread": true], fingerprint: "read", modifiedAt: past))
            case 1:
                XCTAssertEqual(monitor.receipts["thread"]?.isRead, true)
                phase = 2
                reader.set(nil)
            default:
                XCTAssertTrue(monitor.receipts.isEmpty)
                observed.fulfill()
                monitor.stop()
            }
        }
        monitor.start()
        monitor.updateCompletions([completion])
        defer { monitor.stop(); monitor.onChange = nil }
        wait(for: [observed], timeout: 3)
    }
}
