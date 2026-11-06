import SwiftUI

struct ReaderWindowView: View {
    @ObservedObject var model: ReaderWindowModel
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var scale = 100
    private var language: AppLanguage { AppLanguage.fromStoredValue(languageRaw) }
    private var factor: CGFloat { CGFloat(scale) / 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(language.localized(chinese: "文字大小", english: "Text size", russian: "Размер текста"), selection: $scale) {
                ForEach([100, 125, 150], id: \.self) { Text("\($0)%").tag($0) }
            }.pickerStyle(.segmented).font(.system(size: 13 * factor))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    quota(model.content.usage?.weeklyWindow,
                        title: language.localized(chinese: "每周额度", english: "Weekly quota", russian: "Недельная квота"))
                    if let five = model.content.usage?.fiveHourWindow {
                        quota(five, title: language.localized(chinese: "五小时额度", english: "Five-hour quota", russian: "Квота на пять часов"))
                    }
                    if !model.content.conversations.isEmpty {
                        Text(language.localized(chinese: "最近对话", english: "Recent conversations", russian: "Недавние чаты"))
                            .font(.system(size: 17 * factor, weight: .semibold))
                        ForEach(model.content.projectSections, id: \.project.id) { section in
                            Text(section.title(language: language)).font(.system(size: 14 * factor, weight: .semibold))
                            ForEach(section.conversations) { conversation in
                                Button { model.openThread(conversation.threadID) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(conversation.title ?? NotchText.projectName(cwd: conversation.cwd, language: language))
                                            .font(.system(size: 15 * factor))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(conversation.attention.label(language: language))
                                            .font(.system(size: 12 * factor)).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(20)
    }

    private func quota(_ window: UsageWindow?, title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 17 * factor, weight: .semibold))
            if let window {
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(.system(size: 20 * factor))
                if let reset = window.resetAt {
                    Text(language.localized(chinese: "重置于 \(NotchText.resetTimestamp(reset))", english: "Resets at \(NotchText.resetTimestamp(reset))", russian: "Сброс: \(NotchText.resetTimestamp(reset))"))
                        .font(.system(size: 13 * factor)).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("—").font(.system(size: 20 * factor))
            }
        }
    }
}
