import Foundation
import SQLite3

protocol ThreadProjectReading {
    func projects(for threadIDs: [String]) -> [String: NativeThreadProject]
}

struct NativeThreadProject: Equatable, Sendable {
    let id: String
    let name: String?
}

/// Fresh, narrowly scoped read-only metadata lookup. Never queries paths, messages,
/// authentication, native project positions or all project/thread records.
final class CodexThreadProjectReader: ThreadProjectReading {
    private let databaseURL: URL
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(codexHomeURL: URL) { databaseURL = codexHomeURL.appendingPathComponent("state_5.sqlite") }

    func projects(for threadIDs: [String]) -> [String: NativeThreadProject] {
        let ids = Array(Set(threadIDs.filter { Self.validIdentifier($0) })).sorted()
        guard !ids.isEmpty else { return [:] }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database = handle else {
            if let handle { sqlite3_close(handle) }
            return [:]
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 25)
        var result: [String: NativeThreadProject] = [:]
        for start in stride(from: 0, to: ids.count, by: 900) {
            let batch = Array(ids[start..<min(start + 900, ids.count)])
            let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
            let sql = """
                SELECT t.id, t.project_id, p.name FROM threads AS t
                LEFT JOIN projects AS p ON p.id = t.project_id
                WHERE t.id IN (\(placeholders))
                """
            var raw: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &raw, nil) == SQLITE_OK, let statement = raw else { return [:] }
            defer { sqlite3_finalize(statement) }
            for (index, id) in batch.enumerated() {
                guard sqlite3_bind_text(statement, Int32(index + 1), id, -1, Self.transient) == SQLITE_OK else { return [:] }
            }
            var step = sqlite3_step(statement)
            while step == SQLITE_ROW {
                if let id = Self.text(statement, 0, maxBytes: 256), Self.validIdentifier(id),
                   let projectID = Self.text(statement, 1, maxBytes: 256), Self.validIdentifier(projectID) {
                    result[id] = NativeThreadProject(id: projectID, name: Self.text(statement, 2, maxBytes: 1024))
                }
                step = sqlite3_step(statement)
            }
            guard step == SQLITE_DONE else { return [:] }
        }
        return result
    }

    private static func validIdentifier(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 256
            && !id.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32, maxBytes: Int) -> String? {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT, (1...maxBytes).contains(count),
              let text = sqlite3_column_text(statement, column) else { return nil }
        return String(data: Data(bytes: text, count: count), encoding: .utf8)
    }
}
