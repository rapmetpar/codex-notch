import Foundation

/// A local acknowledgement of one completed turn, never a Codex read receipt.
struct ConversationReadReceipt: Codable, Equatable, Sendable {
    let turnID: String
    let completedAt: Date

    init(_ completion: CompletedSession) {
        turnID = completion.session.turnID
        completedAt = completion.completedAt
    }
}

final class ConversationReadStore {
    static let storageKey = "conversationReadReceipts.v1"
    static let maximumReceipts = 512

    private let defaults: UserDefaults
    private(set) var receipts: [String: ConversationReadReceipt]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        receipts = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: ConversationReadReceipt].self, from: $0) } ?? [:]
    }

    @discardableResult
    func acknowledge(_ completion: CompletedSession, threadLinkOpened: Bool) -> Bool {
        guard threadLinkOpened else { return false }
        let receipt = ConversationReadReceipt(completion)
        let threadID = completion.session.threadID
        guard receipts[threadID] != receipt else { return false }
        receipts[threadID] = receipt
        // Keep only small identifiers and completion instants, never titles,
        // paths or conversation contents. This is not a second history cache.
        if receipts.count > Self.maximumReceipts {
            let retained = receipts.filter { $0.key != threadID }.sorted {
                if $0.value.completedAt == $1.value.completedAt { return $0.key < $1.key }
                return $0.value.completedAt > $1.value.completedAt
            }.prefix(Self.maximumReceipts - 1)
            receipts = Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
            receipts[threadID] = receipt
        }
        if let data = try? JSONEncoder().encode(receipts) {
            defaults.set(data, forKey: Self.storageKey)
        }
        return true
    }
}

enum ConversationAttention: CaseIterable, Equatable, Sendable {
    case running
    case unread
    case viewed

    func label(language: AppLanguage) -> String {
        switch self {
        case .running:
            return language.localized(chinese: "运行中", english: "Running", russian: "В работе")
        case .unread:
            return language.localized(chinese: "新回复", english: "New", russian: "Новое")
        case .viewed:
            return language.localized(chinese: "已查看", english: "Viewed", russian: "Просмотрено")
        }
    }

    func hint(language: AppLanguage) -> String {
        switch self {
        case .running:
            return language.localized(chinese: "打开正在运行的对话", english: "Open the running conversation", russian: "Открыть чат в работе")
        case .unread:
            return language.localized(chinese: "完成后尚未从 CodexNotch 打开", english: "Not opened from CodexNotch since completion", russian: "После завершения ещё не открывали из CodexNotch")
        case .viewed:
            return language.localized(chinese: "完成后已从 CodexNotch 打开", english: "Opened from CodexNotch after completion", russian: "Открывали из CodexNotch после завершения")
        }
    }
}
