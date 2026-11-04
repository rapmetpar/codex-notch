import CryptoKit
import Foundation
import SQLite3

struct NativeThreadReadSnapshot: Equatable {
    // true = read, false = unread; missing = unknown.
    let status: [String: Bool]
    let fingerprint: String
    let modifiedAt: Date
    var updatedAt: [String: Date] = [:]
    var scope: String = "fixture"
}

protocol NativeThreadReadSnapshotReading {
    func snapshot(for threadIDs: [String]) -> NativeThreadReadSnapshot?
}

private struct NativeReadEnvelope: Decodable {
    let readState: NativeReadState
    enum CodingKeys: String, CodingKey { case readState = "electron-thread-read-state-v1" }
}

private struct NativeReadState: Decodable {
    let version: Int
    let unreadByIdentity: [String: [String: [String]]]
    let legacyMigration: Migration
    struct Migration: Decodable {
        let identityKey: String
        let adoptedHostIds: [String: String]
        let cleared: Bool?
    }
}

/// Reads only native unread metadata and the requested threads' ownership metadata.
/// The native state is thread-scoped; it does not contain publication identifiers.
final class NativeThreadReadSnapshotReader: NativeThreadReadSnapshotReading {
    private let home: URL
    init(codexHomeURL: URL) { home = codexHomeURL }

    func snapshot(for threadIDs: [String]) -> NativeThreadReadSnapshot? {
        let url = home.appendingPathComponent(".codex-global-state.json")
        guard let before = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = before[.modificationDate] as? Date,
              let size = before[.size] as? NSNumber, size.intValue <= 16_000_000,
              let data = try? Data(contentsOf: url),
              let after = try? FileManager.default.attributesOfItem(atPath: url.path),
              (before as NSDictionary).isEqual(to: after),
              let envelope = try? JSONDecoder().decode(NativeReadEnvelope.self, from: data),
              envelope.readState.version == 1,
              envelope.readState.unreadByIdentity.count == 1,
              let identity = envelope.readState.unreadByIdentity.first,
              envelope.readState.legacyMigration.cleared != true,
              envelope.readState.legacyMigration.identityKey == identity.key,
              let host = envelope.readState.legacyMigration.adoptedHostIds["local"], host.hasPrefix("local:"),
              identity.value.keys.filter({ $0.hasPrefix("local:") }).count == 1,
              let unread = identity.value[host],
              unread.allSatisfy({ Self.valid($0) }) else { return nil }
        let known = knownThreads(threadIDs, matching: identity.key)
        guard let known else { return nil }
        let unreadSet = Set(unread)
        let status = Dictionary(uniqueKeysWithValues: known.ids.map { ($0, !unreadSet.contains($0)) })
        // Fingerprint only the relevant native scoped list, not unrelated JSON.
        let material = ([identity.key, host] + unread.sorted()).joined(separator: "\n")
        let fingerprint = SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
        let scope = SHA256.hash(data: Data((identity.key + "\n" + host).utf8)).map { String(format: "%02x", $0) }.joined()
        return NativeThreadReadSnapshot(status: status, fingerprint: fingerprint, modifiedAt: modified, updatedAt: known.updatedAt, scope: scope)
    }

    private func knownThreads(_ ids: [String], matching identity: String) -> (ids: [String], updatedAt: [String: Date])? {
        let ids = Array(Set(ids.filter(Self.valid))).sorted()
        guard !ids.isEmpty else { return ([], [:]) }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(home.appendingPathComponent("state_5.sqlite").path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db = handle else { if let handle { sqlite3_close(handle) }; return nil }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 25)
        var output: [String] = []
        var updatedAt: [String: Date] = [:]
        var columns: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(threads)", -1, &columns, nil) == SQLITE_OK, let columns else { return nil }
        var hasMilliseconds = false
        while sqlite3_step(columns) == SQLITE_ROW {
            if let name = Self.text(columns, 1), name == "updated_at_ms" { hasMilliseconds = true }
        }
        sqlite3_finalize(columns)
        let updatedColumn = hasMilliseconds ? "updated_at_ms" : "NULL"
        for start in stride(from: 0, to: ids.count, by: 900) {
            let batch = Array(ids[start..<min(start + 900, ids.count)])
            let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT id, creator_account_id, creator_user_id, \(updatedColumn) FROM threads WHERE id IN (\(placeholders))", -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
            defer { sqlite3_finalize(stmt) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (i, id) in batch.enumerated() { guard sqlite3_bind_text(stmt, Int32(i + 1), id, -1, transient) == SQLITE_OK else { return nil } }
            var step = sqlite3_step(stmt)
            while step == SQLITE_ROW {
                if let id = Self.text(stmt, 0), let account = Self.text(stmt, 1), let user = Self.text(stmt, 2),
                   let material = try? JSONSerialization.data(withJSONObject: ["chatgpt", account, user], options: [.fragmentsAllowed, .withoutEscapingSlashes]),
                   SHA256.hash(data: material).map({ String(format: "%02x", $0) }).joined() == identity {
                    output.append(id)
                    if sqlite3_column_type(stmt, 3) == SQLITE_INTEGER {
                        let milliseconds = sqlite3_column_int64(stmt, 3)
                        if milliseconds > 0 { updatedAt[id] = Date(timeIntervalSince1970: Double(milliseconds) / 1000) }
                    }
                }
                step = sqlite3_step(stmt)
            }
            guard step == SQLITE_DONE else { return nil }
        }
        return (output, updatedAt)
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              (1...256).contains(Int(sqlite3_column_bytes(statement, column))),
              let bytes = sqlite3_column_text(statement, column),
              let value = String(data: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column))), encoding: .utf8), valid(value) else { return nil }
        return value
    }
    private static func valid(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && !value.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }
    }
}

/// Binds snapshots to immutable completions. A changed thread-scoped list and
/// post-completion file modification are a freshness heuristic, not a causal token.
struct NativeThreadReadPolicy {
    private let startedAt: Date
    private var completions: [String: ConversationReadReceipt] = [:]
    private var baselines: [String: String] = [:]
    private var trusted: Set<String> = []
    private var lastFingerprint: String?
    private var lastScope: String?
    init(startedAt: Date) { self.startedAt = startedAt }
    mutating func update(_ current: [String: ConversationReadReceipt]) {
        for (id, value) in current where completions[id] != value {
            trusted.remove(id)
            if value.completedAt < startedAt { trusted.insert(id) }
            else { baselines[id] = lastFingerprint ?? "" }
        }
        completions = current
        trusted.formIntersection(current.keys)
        baselines = baselines.filter { current[$0.key] != nil }
    }
    mutating func apply(snapshot: NativeThreadReadSnapshot?) -> [String: NativeConversationReadReceipt] {
        guard let snapshot else { return [:] }
        if let lastScope, lastScope != snapshot.scope {
            trusted = Set(completions.filter { $0.value.completedAt < startedAt }.keys)
            baselines = Dictionary(uniqueKeysWithValues: completions.keys.map { ($0, snapshot.fingerprint) })
        }
        lastScope = snapshot.scope
        var result: [String: NativeConversationReadReceipt] = [:]
        for (id, completion) in completions {
            guard let isRead = snapshot.status[id] else { continue }
            if !trusted.contains(id), let updated = snapshot.updatedAt[id],
               updated >= completion.completedAt.addingTimeInterval(-1) {
                // A post-completion lookup of the native snapshot plus current
                // thread metadata can establish eventual thread-level state.
                // It is not a native per-turn acknowledgement.
                trusted.insert(id)
            } else if !trusted.contains(id), baselines[id] == "" {
                // With no pre-completion sample, the first snapshot is only a
                // baseline, even if another client recently rewrote the file.
                baselines[id] = snapshot.fingerprint
            } else if !trusted.contains(id), snapshot.modifiedAt > completion.completedAt,
                      snapshot.fingerprint != baselines[id] {
                trusted.insert(id)
            }
            guard trusted.contains(id) else { continue }
            result[id] = NativeConversationReadReceipt(turnID: completion.turnID, isRead: isRead)
        }
        lastFingerprint = snapshot.fingerprint
        return result
    }
}
