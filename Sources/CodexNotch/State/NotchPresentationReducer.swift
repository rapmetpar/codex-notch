import Foundation

enum NotchPresentationReducer {
    static func reduce(_ input: NotchPresentationInput) -> NotchPresentationState {
        let sessions = input.activeSessions.sorted { $0.lastActivityAt > $1.lastActivityAt }

        if input.isHovered {
            return .expanded(expandedContent(input: input, sessions: sessions))
        }
        if let primary = sessions.first {
            return .workingCompact(
                primary: primary,
                count: sessions.count,
                usage: input.usage
            )
        }
        if let completion = input.recentCompletions.first {
            // The compact island still shows quota on the right, while its
            // left app mark remains a completion acknowledgement until the
            // next active task supersedes it. Recent-completion history is
            // already retained by ActiveSessionStore, so do not discard this
            // visible state after a couple of seconds.
            return .completedCompact(completion.session, usage: input.usage)
        }

        return .quotaCompact(input.usage)
    }

    private static func expandedContent(
        input: NotchPresentationInput,
        sessions: [SessionActivity]
    ) -> ExpandedContent {
        var seenThreadIDs = Set<String>()
        var conversations: [ConversationSummary] = []

        for session in sessions where seenThreadIDs.insert(session.threadID).inserted {
            conversations.append(
                ConversationSummary(
                    session: session,
                    activity: .running(startedAt: session.startedAt)
                )
            )
        }
        let completions = input.recentCompletions.enumerated().sorted { lhs, rhs in
            if lhs.element.completedAt != rhs.element.completedAt {
                return lhs.element.completedAt > rhs.element.completedAt
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        for completion in completions
            where seenThreadIDs.insert(completion.session.threadID).inserted {
            conversations.append(
                ConversationSummary(
                    session: completion.session,
                    activity: .completed(completedAt: completion.completedAt),
                    isViewed: input.readReceipts[completion.session.threadID]
                        == ConversationReadReceipt(completion)
                        || input.nativeReadReceipts[completion.session.threadID]?.turnID
                            == completion.session.turnID
                )
            )
        }

        return ExpandedContent(
            sessions: sessions,
            // Group every candidate before either ceiling. In particular,
            // running rows must not evict the preferred completed category.
            conversations: Array(
                input.conversationCategoryOrder.sorted(conversations)
                    .prefix(RecentConversationLimit.maximumCount)
            ),
            headerConversation: conversations.first,
            usage: input.usage
        )
    }
}
