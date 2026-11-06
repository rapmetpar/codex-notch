import Foundation

struct ConversationQuery {
    var text = ""
    var attention: ConversationAttention?

    func matching(_ conversations: [ConversationSummary], language: AppLanguage) -> [ConversationSummary] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return conversations.filter { row in
            guard attention == nil || row.attention == attention else { return false }
            guard !query.isEmpty else { return true }
            return (row.title ?? "").localizedStandardContains(query)
                || row.project.title(language: language).localizedStandardContains(query)
        }
    }
}
