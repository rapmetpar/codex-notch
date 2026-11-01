import Foundation
import SQLite3
import XCTest
@testable import CodexNotch

final class CodexThreadProjectReaderTests: XCTestCase {
    private func fixture(_ sql: String) throws -> (URL, CodexThreadProjectReader) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try execute(sql, at: folder)
        return (folder, CodexThreadProjectReader(codexHomeURL: folder))
    }
    private func execute(_ sql: String, at folder: URL) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(folder.appendingPathComponent("state_5.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "SQLiteFixture", code: Int(sqlite3_errcode(db)))
        }
    }
    private let schema = """
        CREATE TABLE threads(id TEXT PRIMARY KEY, project_id TEXT);
        CREATE TABLE projects(id TEXT PRIMARY KEY, name TEXT);
        INSERT INTO projects VALUES ('one', 'Same name'), ('two', 'Same name');
        INSERT INTO threads VALUES ('known', 'one'), ('other', 'two'), ('unset', NULL), ('orphan', 'removed');
        """

    func testOnlyKnownIDsAreReadAndNativeSameNameIdentitySurvivesRenameAndDeletionWithoutWrites() throws {
        let (folder, reader) = try fixture(schema)
        defer { try? FileManager.default.removeItem(at: folder) }
        let db = folder.appendingPathComponent("state_5.sqlite")
        let before = try Data(contentsOf: db)
        let result = reader.projects(for: ["known", "known", "unset", "orphan", "missing", "' OR 1=1 --"])
        XCTAssertEqual(result, ["known": NativeThreadProject(id: "one", name: "Same name"),
                                "orphan": NativeThreadProject(id: "removed", name: nil)])
        XCTAssertEqual(try Data(contentsOf: db), before)
        XCTAssertNil(result["other"])
        XCTAssertEqual(reader.projects(for: []), [:])
        try execute("UPDATE projects SET name='Renamed' WHERE id='one'", at: folder)
        XCTAssertEqual(reader.projects(for: ["known"])["known"], NativeThreadProject(id: "one", name: "Renamed"))
        try execute("DELETE FROM projects WHERE id='one'", at: folder)
        XCTAssertEqual(reader.projects(for: ["known"])["known"], NativeThreadProject(id: "one", name: nil))
    }

    func testMissingSchemaMissingDatabaseInvalidTypesAndCorruptionUseMetadataFallback() throws {
        let (folder, reader) = try fixture("CREATE TABLE threads(id TEXT, cwd TEXT)")
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(reader.projects(for: ["known"]), [:])
        let db = folder.appendingPathComponent("state_5.sqlite")
        try FileManager.default.removeItem(at: db)
        XCTAssertEqual(reader.projects(for: ["known"]), [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: db.path), "Read-only lookup cannot create a missing DB")
        try Data("invalid SQLite".utf8).write(to: db)
        XCTAssertEqual(reader.projects(for: ["known"]), [:])
        try FileManager.default.removeItem(at: db)
        try execute("""
            CREATE TABLE threads(id TEXT, project_id);
            CREATE TABLE projects(id TEXT, name);
            INSERT INTO threads VALUES ('number', 42), ('blob', X'ff'), ('empty', ''), ('bad-space', 'bad id');
            """, at: folder)
        XCTAssertEqual(reader.projects(for: ["number", "blob", "empty", "bad-space"]), [:])
    }

    func testFreshReadObservesWALAndDatabaseReplacementAndLockHasBoundedFallback() throws {
        let (folder, reader) = try fixture(schema)
        defer { try? FileManager.default.removeItem(at: folder) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(folder.appendingPathComponent("state_5.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA journal_mode=WAL; UPDATE threads SET project_id='two' WHERE id='known';", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(reader.projects(for: ["known"])["known"]?.id, "two")
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE; BEGIN EXCLUSIVE;", nil, nil, nil), SQLITE_OK)
        let start = Date()
        XCTAssertEqual(reader.projects(for: ["known"]), [:])
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        XCTAssertEqual(sqlite3_exec(db, "ROLLBACK;", nil, nil, nil), SQLITE_OK)
        let (replacement, _) = try fixture(schema + "UPDATE threads SET project_id='replacement' WHERE id='known';")
        defer { try? FileManager.default.removeItem(at: replacement) }
        _ = try FileManager.default.replaceItemAt(folder.appendingPathComponent("state_5.sqlite"),
                                                   withItemAt: replacement.appendingPathComponent("state_5.sqlite"))
        XCTAssertEqual(reader.projects(for: ["known"])["known"]?.id, "replacement")
    }

    func testNativeMetadataAndNativeReceiptCombineBeforeProjectLimit() throws {
        let (folder, reader) = try fixture(schema + """
            CREATE TABLE thread_read_receipts(thread_id TEXT, first_unread_turn TEXT, revision TEXT, last_published_turn TEXT);
            INSERT INTO thread_read_receipts VALUES ('known', NULL, 'r1', 'finished');
            """)
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date()
        func completion(_ id: String) -> CompletedSession {
            CompletedSession(session: SessionActivity(threadID: id, turnID: "finished", cwd: "/fallback",
                originator: nil, startedAt: now, lastActivityAt: now), completedAt: now)
        }
        var input = NotchPresentationInput(now: now, isChatGPTFrontmost: false, activeSessions: [],
            recentCompletions: [completion("other"), completion("known")], usage: nil, isHovered: true,
            nativeReadReceipts: CodexConversationReadReader(codexHomeURL: folder).receipts(for: ["known", "other"]),
            threadProjects: reader.projects(for: ["known", "other"]),
            conversationProjectOrder: ConversationProjectOrder(ids: [ConversationProject.native(id: "one", name: nil, cwd: nil).id]))
        guard case let .expanded(content) = NotchPresentationReducer.reduce(input).limitingRecentConversations(to: .one)
        else { return XCTFail() }
        XCTAssertEqual(content.conversations.first?.threadID, "known")
        XCTAssertEqual(content.conversations.first?.attention, .viewed)
        input = input.replacing(activeSessions: [completion("other").session], isHovered: false)
        guard case let .workingCompact(primary, _, _) = NotchPresentationReducer.reduce(input) else { return XCTFail() }
        XCTAssertEqual(primary.threadID, "other")
    }
}
