import SwiftUI

final class ActionPanelModel: ObservableObject {
    @Published var conversations: [ConversationSummary] = []
    @Published var usage: UsageSnapshot?
    @Published var language: AppLanguage = .defaultLanguage
    @Published var selectedID: String?

    func adjacentID(to focusedID: String?, forward: Bool) -> String? {
        let ids = conversations.map(\.threadID)
        guard !ids.isEmpty else { return nil }
        let index = focusedID.flatMap { ids.firstIndex(of: $0) }
        return forward ? ids[min((index ?? -1) + 1, ids.count - 1)]
            : ids[max((index ?? ids.count) - 1, 0)]
    }

    func update(content: ExpandedContent, language: AppLanguage) {
        conversations = content.conversations
        usage = content.usage
        self.language = language
    }
}

struct ActionPanelView: View {
    @ObservedObject var model: ActionPanelModel
    let openThread: (String) -> Void
    let dismiss: () -> Void
    @Environment(\.openSettings) private var openSettings
    @FocusState private var focusedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.language.localized(chinese: "操作", english: "Actions", russian: "Действия"))
                .font(.title2.bold())
            Text(quotaText)
            Button(model.language.localized(chinese: "设置…", english: "Settings…", russian: "Настройки…")) {
                SettingsWindowPresenter.show { openSettings() }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(model.conversations) { conversation in
                            Button {
                                openThread(conversation.threadID)
                            } label: {
                                HStack {
                                    Text(conversation.title ?? NotchText.projectName(cwd: conversation.cwd, language: model.language))
                                    Spacer()
                                    Text(conversation.attention.label(language: model.language)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }
                            .id(conversation.threadID)
                            .focused($focusedID, equals: conversation.threadID)
                        }
                    }
                }
                .onChange(of: focusedID) { _, id in
                    model.selectedID = id
                    if let id { proxy.scrollTo(id) }
                }
                .onChange(of: model.selectedID) { _, id in
                    if focusedID != id { focusedID = id }
                }
            }
        }
        .padding(20)
        .onAppear { focusedID = model.selectedID }
        .onExitCommand(perform: dismiss)
        .onMoveCommand { direction in
            switch direction {
            case .down: focusedID = model.adjacentID(to: focusedID, forward: true)
            case .up: focusedID = model.adjacentID(to: focusedID, forward: false)
            default: break
            }
        }
    }

    private var quotaText: String {
        let label = model.language.localized(chinese: "每周额度", english: "Weekly quota", russian: "Недельная квота")
        guard let remaining = model.usage?.weeklyWindow?.remainingPercent else { return "\(label): —" }
        return "\(label): \(Int(remaining.rounded()))%"
    }
}
