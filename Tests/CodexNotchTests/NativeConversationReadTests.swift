import Foundation
import SQLite3
import XCTest
@testable import CodexNotch

final class NativeConversationReadTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private final class Database {
        let home: URL
        let url: URL
        var writer: OpaquePointer?
        var reader: CodexConversationReadReader { CodexConversationReadReader(codexHomeURL: home) }

        init(schema: Bool = true, wal: Bool = false) throws {
            home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            url = home.appendingPathComponent("state_5.sqlite")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            XCTAssertEqual(sqlite3_open(url.path, &writer), SQLITE_OK)
            if wal { try execute("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;") }
            if schema {
                try execute("CREATE TABLE thread_read_receipts(thread_id TEXT PRIMARY KEY, first_unread_turn TEXT, revision TEXT NOT NULL, last_published_turn TEXT)")
            }
        }

        deinit {
            sqlite3_close(writer)
            try? FileManager.default.removeItem(at: home)
        }

        func execute(_ sql: String) throws {
            guard sqlite3_exec(writer, sql, nil, nil, nil) == SQLITE_OK else {
                throw NSError(domain: "SyntheticReceiptDatabase", code: Int(sqlite3_errcode(writer)))
            }
        }

        func receipt(_ thread: String = "thread", unread: String? = nil, turn: String? = "turn-1", revision: String = "revision-1") throws {
            var statement: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(writer, "INSERT OR REPLACE INTO thread_read_receipts VALUES(?,?,?,?)", -1, &statement, nil), SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (index, value) in [thread, unread, revision, turn].enumerated() {
                if let value { sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) }
                else { sqlite3_bind_null(statement, Int32(index + 1)) }
            }
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        }
    }

    private func completion(thread: String = "thread", turn: String = "turn-1") -> CompletedSession {
        CompletedSession(session: SessionActivity(threadID: thread, turnID: turn, title: nil, cwd: nil,
            originator: nil, startedAt: now.addingTimeInterval(-100), lastActivityAt: now), completedAt: now)
    }

    private func attention(_ completion: CompletedSession, native: [String: NativeConversationReadReceipt],
                           local: [String: ConversationReadReceipt] = [:], running: Bool = false) -> ConversationAttention? {
        let input = NotchPresentationInput(now: now, isChatGPTFrontmost: false,
            activeSessions: running ? [completion.session] : [], recentCompletions: [completion], usage: nil,
            isHovered: true, readReceipts: local, nativeReadReceipts: native)
        guard case let .expanded(content) = NotchPresentationReducer.reduce(input) else { return nil }
        return content.conversations.first?.attention
    }

    func testNativeReadOfExactPublishedTurnViewsAnswerWithoutNotchClick() throws {
        let db = try Database()
        try db.receipt()
        XCTAssertEqual(attention(completion(), native: db.reader.receipts(for: ["thread"])), .viewed)
    }

    func testOldReadCannotHideNewAnswerAndRunningAlwaysWins() throws {
        let db = try Database()
        try db.receipt()
        let native = db.reader.receipts(for: ["thread"])
        XCTAssertEqual(attention(completion(turn: "turn-2"), native: native), .unread)
        XCTAssertEqual(attention(completion(), native: native, local: ["thread": ConversationReadReceipt(completion())], running: true), .running)
        try db.receipt(unread: "turn-2", turn: "turn-2", revision: "revision-2")
        XCTAssertEqual(attention(completion(turn: "turn-2"), native: db.reader.receipts(for: ["thread"])), .unread)
    }

    func testNativeUnreadIncludingManualEmptyMarkerIsNotAReadReceipt() throws {
        let db = try Database()
        for unread in ["turn-1", ""] {
            try db.receipt(unread: unread)
            XCTAssertEqual(attention(completion(), native: db.reader.receipts(for: ["thread"])), .unread)
        }
    }

    func testMissingOldMalformedAndUnavailableDataFallBackToLocalAcknowledgement() throws {
        let db = try Database()
        let finished = completion()
        let local = ["thread": ConversationReadReceipt(finished)]
        func checkFallback() {
            let native = db.reader.receipts(for: ["thread"])
            XCTAssertEqual(attention(finished, native: native), .unread)
            XCTAssertEqual(attention(finished, native: native, local: local), .viewed)
            XCTAssertEqual(attention(completion(turn: "turn-2"), native: native, local: local), .unread)
        }
        checkFallback()
        try db.receipt(turn: "old-turn")
        checkFallback()
        try db.receipt(turn: nil)
        checkFallback()
        for revision in ["", " ", String(repeating: "x", count: 257)] {
            try db.receipt(revision: revision)
            checkFallback()
        }
        try db.execute("UPDATE thread_read_receipts SET last_published_turn=x'7475726e2d31'")
        checkFallback()
        try db.execute("DROP TABLE thread_read_receipts")
        checkFallback()
    }

    func testLocalHandoffRemainsValidWhileNativeReceiptStillSaysUnread() throws {
        let db = try Database()
        try db.receipt(unread: "turn-1")
        XCTAssertEqual(attention(completion(), native: db.reader.receipts(for: ["thread"]),
            local: ["thread": ConversationReadReceipt(completion())]), .viewed)
    }

    func testNativeReadDoesNotChangeCompactCompletionHistoryOrderOrLimits() {
        let first = completion()
        let second = completion(thread: "older")
        var input = NotchPresentationInput(now: now, isChatGPTFrontmost: false,
            activeSessions: [], recentCompletions: [first, second], usage: nil, isHovered: false)
        let compact = NotchPresentationReducer.reduce(input)
        input.nativeReadReceipts = ["thread": NativeConversationReadReceipt(turnID: "turn-1")]
        XCTAssertEqual(NotchPresentationReducer.reduce(input), compact)
        let expanded = NotchPresentationInput(now: now, isChatGPTFrontmost: false,
            activeSessions: [], recentCompletions: [first, second], usage: nil, isHovered: true,
            nativeReadReceipts: input.nativeReadReceipts)
        guard case let .expanded(content) = NotchPresentationReducer.reduce(expanded) else { return XCTFail("Expected expanded") }
        XCTAssertEqual(content.conversations.map(\.threadID), ["thread", "older"])
        XCTAssertEqual(content.conversations.map(\.attention), [.viewed, .unread])
        XCTAssertTrue(content.limitingRecentConversations(to: .none).conversations.isEmpty)
    }

    func testReaderObservesWALCommitsAndClearsRemovedReceiptsWithoutRecreation() throws {
        let db = try Database(wal: true)
        let reader = db.reader
        try db.receipt(unread: "turn-1")
        XCTAssertEqual(attention(completion(), native: reader.receipts(for: ["thread"])), .unread)
        try db.receipt(revision: "read-revision")
        XCTAssertEqual(attention(completion(), native: reader.receipts(for: ["thread"])), .viewed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: db.url.path + "-wal"))
        try db.execute("DELETE FROM thread_read_receipts")
        XCTAssertEqual(attention(completion(), native: reader.receipts(for: ["thread"])), .unread)
    }

    func testReaderReopensAtomicallyReplacedDatabaseAndRecoversAfterDisappearance() throws {
        let db = try Database()
        let reader = db.reader
        try db.receipt()
        XCTAssertEqual(attention(completion(), native: reader.receipts(for: ["thread"])), .viewed)
        let replacement = try Database()
        try replacement.receipt(unread: "turn-1")
        XCTAssertEqual(rename(replacement.url.path, db.url.path), 0)
        XCTAssertEqual(attention(completion(), native: reader.receipts(for: ["thread"])), .unread)
        try FileManager.default.removeItem(at: db.url)
        XCTAssertTrue(reader.receipts(for: ["thread"]).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: db.url.path), "Read-only lookup must not create a missing database")
        let recovered = try Database()
        try recovered.receipt()
        XCTAssertEqual(rename(recovered.url.path, db.url.path), 0)
        XCTAssertEqual(attention(completion(), native: reader.receipts(for: ["thread"])), .viewed)
    }

    func testLockedCorruptAndLegacySchemasFailClosedWithoutBlockingLocalState() throws {
        let db = try Database()
        let reader = db.reader
        try db.receipt()
        try db.execute("BEGIN EXCLUSIVE")
        XCTAssertTrue(reader.receipts(for: ["thread"]).isEmpty)
        try db.execute("ROLLBACK")
        XCTAssertEqual(reader.receipts(for: ["thread"])["thread"]?.turnID, "turn-1")
        let legacy = try Database(schema: false)
        try legacy.execute("CREATE TABLE thread_read_receipts(thread_id TEXT PRIMARY KEY, first_unread_turn TEXT, revision TEXT)")
        XCTAssertTrue(legacy.reader.receipts(for: ["thread"]).isEmpty)
        let corrupt = try Database(schema: false)
        sqlite3_close(corrupt.writer)
        corrupt.writer = nil
        try Data("not sqlite".utf8).write(to: corrupt.url)
        XCTAssertTrue(corrupt.reader.receipts(for: ["thread"]).isEmpty)
    }

    func testQueryIsLimitedToRequestedIDsAndDoesNotPersistOrModifyDatabase() throws {
        let db = try Database()
        try db.receipt()
        try db.receipt("unrequested")
        let before = try Data(contentsOf: db.url)
        let result = db.reader.receipts(for: ["thread", "thread", "' OR 1=1 --"])
        XCTAssertEqual(Set(result.keys), ["thread"])
        XCTAssertEqual(try Data(contentsOf: db.url), before)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: db.home.path)), ["state_5.sqlite"])
    }

    private final class DelayedReader: NativeConversationReadReading {
        let firstStarted: XCTestExpectation
        let release = DispatchSemaphore(value: 0)

        init(firstStarted: XCTestExpectation) { self.firstStarted = firstStarted }

        func receipts(for threadIDs: [String]) -> [String: NativeConversationReadReceipt] {
            if threadIDs == ["old"] {
                firstStarted.fulfill()
                _ = release.wait(timeout: .now() + 2)
            }
            return Dictionary(uniqueKeysWithValues: threadIDs.map { ($0, NativeConversationReadReceipt(turnID: "turn-1")) })
        }
    }

    @MainActor
    func testSupersededLookupCannotRestoreRemovedConversationReceipt() {
        let started = expectation(description: "Old lookup started")
        let reader = DelayedReader(firstStarted: started)
        let monitor = NativeConversationReadMonitor(reader: reader)
        let updated = expectation(description: "Only current lookup is published")
        monitor.onChange = {
            XCTAssertEqual(Set(monitor.receipts.keys), ["new"])
            updated.fulfill()
        }
        monitor.updateThreadIDs(["old"])
        monitor.start()
        defer { reader.release.signal(); monitor.stop(); monitor.onChange = nil }
        wait(for: [started], timeout: 1)
        monitor.updateThreadIDs(["new"])
        reader.release.signal()
        wait(for: [updated], timeout: 1)
    }

    @MainActor
    func testStoppedMonitorDoesNotPublishLateReceiptOrRetainNativeState() {
        let started = expectation(description: "Lookup started")
        let reader = DelayedReader(firstStarted: started)
        let monitor = NativeConversationReadMonitor(reader: reader)
        let noLateUpdate = expectation(description: "Stopped runtime must not change")
        noLateUpdate.isInverted = true
        monitor.onChange = { noLateUpdate.fulfill() }
        monitor.updateThreadIDs(["old"])
        monitor.start()
        wait(for: [started], timeout: 1)
        monitor.stop()
        reader.release.signal()
        wait(for: [noLateUpdate], timeout: 0.1)
        XCTAssertTrue(monitor.receipts.isEmpty)
        monitor.onChange = nil
    }

    @MainActor
    func testLiveTimerPublishesNativeReadNewTurnAndLossWithNoRestartOrRolloutChange() throws {
        let db = try Database(wal: true)
        try db.receipt(unread: "turn-1")
        let monitor = NativeConversationReadMonitor(reader: db.reader, refreshInterval: 0.02)
        let viewed = expectation(description: "Native read updates the actual presentation")
        let nextViewed = expectation(description: "Next turn is read separately")
        let lost = expectation(description: "Missing source removes transient native receipt")
        var current = completion()
        var phase = 0
        monitor.onChange = {
            switch phase {
            case 0:
                XCTAssertEqual(self.attention(current, native: monitor.receipts), .viewed)
                viewed.fulfill()
                current = self.completion(turn: "turn-2")
                XCTAssertEqual(self.attention(current, native: monitor.receipts), .unread)
                try! db.receipt(unread: "turn-2", turn: "turn-2", revision: "new-result")
                phase = 1
            case 1:
                XCTAssertEqual(self.attention(current, native: monitor.receipts), .unread)
                try! db.receipt(turn: "turn-2", revision: "new-read")
                phase = 2
            case 2:
                XCTAssertEqual(self.attention(current, native: monitor.receipts), .viewed)
                nextViewed.fulfill()
                try! db.execute("DROP TABLE thread_read_receipts")
                phase = 3
            default:
                XCTAssertEqual(self.attention(current, native: monitor.receipts), .unread)
                lost.fulfill()
                monitor.stop()
            }
        }
        monitor.updateThreadIDs(["thread"])
        monitor.start()
        defer { monitor.stop(); monitor.onChange = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            try! db.receipt(revision: "read-after-native-selection")
        }
        wait(for: [viewed, nextViewed, lost], timeout: 3)
        XCTAssertTrue(monitor.receipts.isEmpty)
    }
}
