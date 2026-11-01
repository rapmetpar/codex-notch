import Foundation

/// Only the optional expanded list follows this order; compact activity does not.
enum ConversationCategoryOrder: String, CaseIterable, Identifiable, Sendable {
    case runningUnreadViewed = "running,unread,viewed"
    case runningViewedUnread = "running,viewed,unread"
    case unreadRunningViewed = "unread,running,viewed"
    case unreadViewedRunning = "unread,viewed,running"
    case viewedRunningUnread = "viewed,running,unread"
    case viewedUnreadRunning = "viewed,unread,running"

    static let storageKey = "conversationCategoryOrder.v1"
    static let defaultOrder: Self = .runningUnreadViewed
    var id: String { rawValue }

    var categories: [ConversationAttention] {
        switch self {
        case .runningUnreadViewed: return [.running, .unread, .viewed]
        case .runningViewedUnread: return [.running, .viewed, .unread]
        case .unreadRunningViewed: return [.unread, .running, .viewed]
        case .unreadViewedRunning: return [.unread, .viewed, .running]
        case .viewedRunningUnread: return [.viewed, .running, .unread]
        case .viewedUnreadRunning: return [.viewed, .unread, .running]
        }
    }

    static func fromStoredValue(_ value: String?) -> Self {
        value.flatMap(Self.init(rawValue:)) ?? .defaultOrder
    }

    func moving(_ category: ConversationAttention, by offset: Int) -> Self {
        var next = categories
        guard let index = next.firstIndex(of: category),
              [-1, 1].contains(offset), next.indices.contains(index + offset) else { return self }
        next.swapAt(index, index + offset)
        return Self.allCases.first { $0.categories == next } ?? self
    }

    func sorted(_ conversations: [ConversationSummary]) -> [ConversationSummary] {
        let categories = self.categories
        return conversations.enumerated().sorted { lhs, rhs in
            let leftRank = categories.firstIndex(of: lhs.element.attention)!
            let rightRank = categories.firstIndex(of: rhs.element.attention)!
            if leftRank != rightRank { return leftRank < rightRank }
            let leftDate = Self.sortDate(lhs.element)
            let rightDate = Self.sortDate(rhs.element)
            if leftDate != rightDate { return leftDate > rightDate }
            // Snapshot arrays can originate from dictionary values. Equal times
            // must not make rows jump after source enumeration changes.
            if lhs.element.threadID != rhs.element.threadID {
                return lhs.element.threadID < rhs.element.threadID
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func sortDate(_ conversation: ConversationSummary) -> Date {
        switch conversation.activity {
        case .running: return conversation.lastActivityAt
        case let .completed(completedAt): return completedAt
        }
    }

    static func title(for category: ConversationAttention, language: AppLanguage) -> String {
        switch category {
        case .running:
            return language.localized(chinese: "运行中", english: "Running", russian: "В работе")
        case .unread:
            return language.localized(chinese: "已完成（新回复）", english: "Completed (new)", russian: "Завершённые (новые)")
        case .viewed:
            return language.localized(chinese: "已查看", english: "Viewed", russian: "Прочитанные")
        }
    }
}
