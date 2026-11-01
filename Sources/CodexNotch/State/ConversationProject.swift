import CryptoKit
import Foundation

/// Only opaque IDs are persisted/transferred. Paths remain existing in-memory row metadata.
struct ConversationProject: Equatable, Identifiable, Sendable {
    let id: String
    let name: String?

    static let unassigned = ConversationProject(id: "unassigned", name: nil)

    static func native(id: String, name: String?, cwd: String?) -> Self {
        Self(id: opaqueID(prefix: "native", value: id), name: cleanName(name) ?? fallback(cwd: cwd).name)
    }

    static func fallback(cwd: String?) -> Self {
        guard let cwd, cwd.hasPrefix("/"), !cwd.contains("\0"), cwd.utf8.count <= 16_384 else {
            return .unassigned
        }
        let url = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        return Self(id: opaqueID(prefix: "cwd", value: url.path), name: cleanName(url.lastPathComponent))
    }

    func title(language: AppLanguage) -> String {
        name ?? language.localized(chinese: "未分配项目", english: "Unassigned", russian: "Без проекта")
    }

    static func isValidID(_ id: String) -> Bool {
        if id == unassigned.id { return true }
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 2 && ["native", "cwd"].contains(String(parts[0]))
            && parts[1].count == 64 && parts[1].allSatisfy { "0123456789abcdef".contains($0) }
    }

    private static func opaqueID(prefix: String, value: String) -> String {
        prefix + ":" + SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func cleanName(_ name: String?) -> String? {
        guard let name else { return nil }
        let value = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        guard !value.isEmpty, value.count <= 96,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return value
    }
}

struct ConversationProjectSection: Equatable, Identifiable, Sendable {
    let project: ConversationProject
    let conversations: [ConversationSummary]
    let distinguishesSameName: Bool
    var id: String { project.id }

    func title(language: AppLanguage) -> String {
        let title = project.title(language: language)
        return distinguishesSameName ? title + " · " + project.id.suffix(6) : title
    }
}

struct ConversationProjectOrder: Equatable, Sendable {
    static let storageKey = "conversationProjectOrder.v1"
    static let maximumStoredProjects = 4096
    var ids: [String] = []

    init(ids: [String] = []) {
        // An invalid order must not silently rank a subset or introduce duplicate headings.
        self.ids = ids.count <= Self.maximumStoredProjects && Set(ids).count == ids.count
            && ids.allSatisfy(ConversationProject.isValidID) ? ids : []
    }

    static func read(from defaults: UserDefaults) -> Self {
        guard let ids = defaults.array(forKey: storageKey) as? [String] else { return Self() }
        return Self(ids: ids)
    }

    func including(_ known: [String]) -> Self {
        var result = ids
        var seen = Set(result)
        for id in known where ConversationProject.isValidID(id) && seen.insert(id).inserted {
            if result.count == Self.maximumStoredProjects { break }
            result.append(id)
        }
        return Self(ids: result)
    }

    func availableIDs(in conversations: [ConversationSummary]) -> [String] {
        let projects = Dictionary(conversations.map { ($0.project.id, $0.project) }, uniquingKeysWith: { first, _ in first })
        // New projects append in a deterministic order, without shuffling existing ranks.
        let discovered = projects.values.sorted {
            if $0.name != $1.name { return ($0.name ?? "") < ($1.name ?? "") }
            return $0.id < $1.id
        }.map(\.id)
        return ids.filter { projects[$0] != nil } + discovered.filter { !ids.contains($0) }
    }

    func sorted(_ conversations: [ConversationSummary], categories: ConversationCategoryOrder) -> [ConversationSummary] {
        let ids = availableIDs(in: conversations)
        return ids.flatMap { id in categories.sorted(conversations.filter { $0.project.id == id }) }
    }
}

/// App-owned preferences only. Native Codex project positions are never read or changed.
final class ConversationProjectOrderStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults }
    var order: ConversationProjectOrder { .read(from: defaults) }

    func discover(_ ids: [String]) {
        save(order.including(ids))
    }

    @discardableResult
    func prioritize(_ ids: [String]) -> Bool {
        guard !ids.isEmpty, ids.count <= ConversationProjectOrder.maximumStoredProjects, Set(ids).count == ids.count,
              ids.allSatisfy(ConversationProject.isValidID) else { return false }
        // Keep dormant/deleted IDs at their prior relative ranks after current projects.
        // Reappearance and rename never drop a conversation or reset visible order.
        save(ConversationProjectOrder(ids: Array((ids + order.ids.filter { !ids.contains($0) }).prefix(ConversationProjectOrder.maximumStoredProjects))))
        return true
    }

    private func save(_ order: ConversationProjectOrder) {
        guard self.order != order else { return }
        defaults.set(order.ids, forKey: ConversationProjectOrder.storageKey)
    }
}
