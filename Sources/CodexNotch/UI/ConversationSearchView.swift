import AppKit
import SwiftUI

final class ConversationSearchModel: ObservableObject {
    @Published var conversations: [ConversationSummary] = []
    @Published var language: AppLanguage = .english
    var onOpen: (String) -> Void = { _ in }

    func open(_ threadID: String) {
        guard conversations.contains(where: { $0.threadID == threadID }) else { return }
        onOpen(threadID)
    }
}

struct ConversationSearchView: View {
    @ObservedObject var model: ConversationSearchModel
    @State private var query = ""
    @State private var category = "all"
    @FocusState private var searchFocused: Bool

    private var language: AppLanguage { model.language }
    private var results: [ConversationSummary] {
        let attention: ConversationAttention? = category == "running" ? .running : category == "unread" ? .unread : category == "viewed" ? .viewed : nil
        return ConversationQuery(text: query, attention: attention).matching(model.conversations, language: language)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.localized(chinese: "仅搜索设置中允许的最近对话", english: "Search only the recent conversations allowed in Settings", russian: "Поиск только среди недавних чатов в пределах настройки"))
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField(language.localized(chinese: "搜索标题或项目", english: "Search titles or projects", russian: "Название чата или проекта"), text: $query)
                    .textFieldStyle(.roundedBorder).focused($searchFocused)
                Button(language.localized(chinese: "清除", english: "Clear", russian: "Очистить")) { query = ""; category = "all" }
            }
            Picker(language.localized(chinese: "状态", english: "Status", russian: "Статус"), selection: $category) {
                Text(language.localized(chinese: "全部", english: "All", russian: "Все")).tag("all")
                Text(ConversationAttention.running.label(language: language)).tag("running")
                Text(ConversationAttention.unread.label(language: language)).tag("unread")
                Text(ConversationAttention.viewed.label(language: language)).tag("viewed")
            }
            if results.isEmpty {
                Text(language.localized(chinese: "最近对话中没有匹配结果", english: "No matches in recent conversations", russian: "Среди недавних чатов совпадений нет"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { row in
                    Button { model.open(row.threadID) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(row.title ?? row.project.title(language: language)).lineLimit(1)
                                Text(row.project.title(language: language)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(row.attention.label(language: language)).foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(16).frame(minWidth: 460, minHeight: 320)
        .onAppear { searchFocused = true }
        .onExitCommand { query = ""; category = "all" }
    }
}

final class ConversationSearchWindow: NSObject, NSWindowDelegate {
    let model = ConversationSearchModel()
    private var window: NSWindow?
    var isOpen: Bool { window != nil }

    func show() {
        if let window { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = model.language.localized(chinese: "搜索最近对话", english: "Search recent conversations", russian: "Поиск недавних чатов")
        window.contentView = NSHostingView(rootView: ConversationSearchView(model: model))
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func close() { window?.close() }
    func windowWillClose(_ notification: Notification) { window = nil; model.conversations = [] }
}
