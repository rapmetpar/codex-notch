import Foundation
import SQLite3

/// In-memory native acknowledgement of a particular published turn. Never persisted.
struct NativeConversationReadReceipt: Equatable, Sendable {
    let turnID: String
}

protocol NativeConversationReadReading {
    func receipts(for threadIDs: [String]) -> [String: NativeConversationReadReceipt]
}

/// Reads only the requested receipt metadata, using a fresh read-only connection
/// each time so WAL commits and atomic database replacement are both observable.
final class CodexConversationReadReader: NativeConversationReadReading {
    private let databaseURL: URL
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(codexHomeURL: URL) {
        databaseURL = codexHomeURL.appendingPathComponent("state_5.sqlite")
    }

    func receipts(for threadIDs: [String]) -> [String: NativeConversationReadReceipt] {
        let ids = Array(Set(threadIDs.filter { Self.isIdentifier($0) })).sorted()
        guard !ids.isEmpty else { return [:] }
        var handle: OpaquePointer?
        let opened = sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard opened == SQLITE_OK, let database = handle else {
            if let handle { sqlite3_close(handle) }
            return [:]
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 25)

        var result: [String: NativeConversationReadReceipt] = [:]
        for start in stride(from: 0, to: ids.count, by: 900) {
            let batch = Array(ids[start..<min(start + 900, ids.count)])
            let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
            let query = """
                SELECT thread_id, first_unread_turn, revision, last_published_turn
                FROM thread_read_receipts WHERE thread_id IN (\(placeholders))
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
                  let statement else { return [:] }
            defer { sqlite3_finalize(statement) }
            for (index, id) in batch.enumerated() {
                guard sqlite3_bind_text(statement, Int32(index + 1), id, -1, Self.sqliteTransient) == SQLITE_OK else {
                    return [:]
                }
            }
            var step = sqlite3_step(statement)
            while step == SQLITE_ROW {
                // NULL alone is insufficient: a missing/legacy publication key
                // cannot acknowledge a new answer. Empty first_unread_turn is
                // explicitly manually unread in Codex, not another form of NULL.
                if sqlite3_column_type(statement, 1) == SQLITE_NULL,
                   let id = Self.identifier(statement, 0),
                   Self.identifier(statement, 2) != nil,
                   let turnID = Self.identifier(statement, 3) {
                    result[id] = NativeConversationReadReceipt(turnID: turnID)
                }
                step = sqlite3_step(statement)
            }
            guard step == SQLITE_DONE else { return [:] }
        }
        return result
    }

    private static func identifier(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              (1...256).contains(Int(sqlite3_column_bytes(statement, column))),
              let bytes = sqlite3_column_text(statement, column) else { return nil }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
        guard let value = String(data: data, encoding: .utf8), isIdentifier(value) else { return nil }
        return value
    }

    private static func isIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256
            && !value.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }
    }
}
