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
        if let completion = input.recentCompletions.first(where: {
            !isViewed($0, input: input) && (
                input.compactCompletionSignals[$0.session.threadID] == ConversationReadReceipt($0)
                    || (input.nativeReadReceipts[$0.session.threadID]?.turnID == $0.session.turnID
                        && input.nativeReadReceipts[$0.session.threadID]?.isRead == false))
        }) {
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
        func project(for session: SessionActivity) -> ConversationProject {
            if let native = input.threadProjects[session.threadID] {
                return .native(id: native.id, name: native.name, cwd: session.cwd)
            }
            return .fallback(cwd: session.cwd)
        }

        for session in sessions where seenThreadIDs.insert(session.threadID).inserted {
            conversations.append(
                ConversationSummary(
                    session: session,
                    activity: .running(startedAt: session.startedAt),
                    project: project(for: session)
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
                    isViewed: isViewed(completion, input: input),
                    project: project(for: completion.session)
                )
            )
        }

        return ExpandedContent(
            sessions: sessions,
            // Group every candidate before either ceiling. In particular,
            // running rows must not evict the preferred completed category.
            conversations: Array(
                input.conversationProjectOrder.sorted(conversations, categories: input.conversationCategoryOrder)
                    .prefix(RecentConversationLimit.maximumCount)
            ),
            headerConversation: conversations.first,
            usage: input.usage,
            allProjectIDs: input.conversationProjectOrder.availableIDs(in: conversations)
        )
    }

    private static func isViewed(_ completion: CompletedSession, input: NotchPresentationInput) -> Bool {
        input.readReceipts[completion.session.threadID] == ConversationReadReceipt(completion)
            || (input.nativeReadReceipts[completion.session.threadID]?.turnID == completion.session.turnID
                && input.nativeReadReceipts[completion.session.threadID]?.isRead == true)
    }
}
