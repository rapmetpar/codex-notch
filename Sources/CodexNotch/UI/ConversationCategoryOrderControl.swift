import SwiftUI

struct ConversationCategoryOrderControl: View {
    @Binding var order: ConversationCategoryOrder
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.localized(chinese: "对话分类顺序", english: "Chat category order", russian: "Порядок категорий чатов"))
            ForEach(Array(order.categories.enumerated()), id: \.offset) { index, category in
                let title = ConversationCategoryOrder.title(for: category, language: language)
                HStack(spacing: 8) {
                    Text("\(index + 1). \(title)")
                    Spacer(minLength: 8)
                    Button {
                        order = order.moving(category, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)
                    .accessibilityLabel(language.localized(
                        chinese: "上移\(title)", english: "Move \(title) up", russian: "Переместить «\(title)» выше"
                    ))
                    Button {
                        order = order.moving(category, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == order.categories.count - 1)
                    .accessibilityLabel(language.localized(
                        chinese: "下移\(title)", english: "Move \(title) down", russian: "Переместить «\(title)» ниже"
                    ))
                }
                .controlSize(.small)
            }
        }
    }
}
