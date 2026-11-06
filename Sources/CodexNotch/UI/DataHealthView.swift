import SwiftUI

struct DataHealthView: View {
    @ObservedObject var model: DataHealth
    var onTitleChange: (String) -> Void = { _ in }
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    private var language: AppLanguage { .fromStoredValue(languageRaw) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(DataHealthText.title(language)).font(.title2.bold())
                Text(language.localized(
                    chinese: "额度更新失败时，刘海区域会保留上次已知数值。任务和阅读状态独立检查。",
                    english: "If a quota update fails, the notch keeps its last known values. Tasks and read status are checked independently.",
                    russian: "Если квоту не удалось обновить, в нотче остаются последние известные значения. Задачи и статус прочтения проверяются отдельно."
                ))
                .font(.callout).foregroundStyle(.secondary)

                row(language.localized(chinese: "额度", english: "Quota", russian: "Квота"),
                    health: model.usage, staleAfter: DataHealth.usageStaleAfter)
                Divider()
                row(language.localized(chinese: "本地任务监测", english: "Local task monitoring", russian: "Мониторинг задач"),
                    health: model.rollouts, staleAfter: DataHealth.rolloutStaleAfter)
                Divider()
                row(language.localized(chinese: "Codex 阅读状态", english: "Codex read metadata", russian: "Статус прочтения в Codex"),
                    health: model.nativeRead, staleAfter: DataHealth.nativeReadStaleAfter)
                Text(language.localized(
                    chinese: "没有已完成的聊天时不会检查阅读状态。来源不可用时，阅读状态未知。",
                    english: "Read status is not checked without completed chats. An unavailable source means read status is unknown.",
                    russian: "Без завершённых чатов прочтение не проверяется. Если источник недоступен, статус прочтения неизвестен."
                ))
                .font(.caption).foregroundStyle(.secondary)

                HStack {
                    Button(language.localized(chinese: "重试额度", english: "Retry Quota", russian: "Повторить запрос квоты")) {
                        model.onRetry?()
                    }
                    .disabled(!model.canRetry)
                    Spacer()
                    Button(language.localized(chinese: "打开 Codex", english: "Open Codex", russian: "Открыть Codex")) {
                        model.onOpenCodex?()
                    }
                    .disabled(!model.isMonitoring)
                }
                Text(language.localized(
                    chinese: "额度每 60 秒自动检查一次。请求期间或两次请求间隔不足 10 秒时，无法重试。",
                    english: "Quota checks run every 60 seconds. Retry is available after the current request finishes and at least 10 seconds after the previous attempt.",
                    russian: "Квота проверяется раз в 60 секунд. Повтор доступен после завершения запроса и не раньше чем через 10 секунд после прошлой попытки."
                ))
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(width: 520, height: 560)
        .onAppear { onTitleChange(DataHealthText.title(language)) }
        .onChange(of: languageRaw) { _, _ in onTitleChange(DataHealthText.title(language)) }
    }

    private func row(_ title: String, health: DataSourceHealth, staleAfter: TimeInterval) -> some View {
        let state = health.state(at: model.now, staleAfter: staleAfter)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(state.title(language: language))
                    .foregroundStyle(state == .stale || state == .unavailable ? Color.orange : Color.secondary)
            }
            Text(DataHealthText.lastSuccess(health.lastSuccessAt, language: language))
                .font(.caption).foregroundStyle(.secondary)
            if health.lastCheckFailed {
                Text(DataHealthText.failure(language)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
