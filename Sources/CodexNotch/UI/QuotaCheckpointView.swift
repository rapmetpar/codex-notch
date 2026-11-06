import SwiftUI

struct QuotaCheckpointView: View {
    @ObservedObject var checkpoint: QuotaCheckpoint
    @AppStorage(AppLanguage.storageKey, store: AppPreferences.store)
    private var languageRaw = AppLanguage.defaultLanguage.rawValue
    private var language: AppLanguage { AppLanguage.fromStoredValue(languageRaw) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 16) {
                Text(language.localized(chinese: "配额检查点", english: "Quota checkpoint", russian: "Контрольная точка квоты"))
                    .font(.headline)
                if let startedAt = checkpoint.startedAt {
                    Text(language.localized(chinese: "开始时间", english: "Started", russian: "Начало") + ": " + startedAt.formatted(date: .abbreviated, time: .standard))
                    row(language.localized(chinese: "5 小时", english: "5 hours", russian: "5 часов"), kind: .rolling(hours: 5), now: context.date)
                    row(language.localized(chinese: "每周", english: "Weekly", russian: "Неделя"), kind: .weekly, now: context.date)
                    Button(language.localized(chinese: "清除", english: "Clear", russian: "Очистить")) { checkpoint.clear() }
                } else {
                    Text(language.localized(chinese: "比较当前剩余额度的变化。", english: "Compare changes in remaining quota.", russian: "Сравните изменение оставшейся квоты."))
                    Button(language.localized(chinese: "创建检查点", english: "Start checkpoint", russian: "Создать точку")) { checkpoint.start(now: context.date) }
                        .disabled(checkpoint.snapshot == nil || checkpoint.lastRefreshFailed || !checkpoint.isFresh(checkpoint.snapshot!, now: context.date))
                }
            }
            .padding(24)
            .frame(width: 380, alignment: .leading)
        }
    }

    private func row(_ title: String, kind: UsageWindowKind, now: Date) -> some View {
        HStack { Text(title); Spacer(); Text(description(checkpoint.comparison(kind: kind, now: now))) }
    }

    private func description(_ comparison: QuotaCheckpoint.Comparison) -> String {
        switch comparison {
        case .change(let value):
            let amount = String(format: "%.1f", abs(value))
            let sign = value < 0 ? "−" : ""
            return "\(sign)\(amount) " + language.localized(chinese: "个百分点", english: "pp", russian: "п.п.")
        case .stale:
            return language.localized(chinese: "数据已过期", english: "Data is stale", russian: "Данные устарели")
        case .unavailable:
            return language.localized(chinese: "不可用", english: "Unavailable", russian: "Нет данных")
        case .incomparable:
            return language.localized(chinese: "无法比较", english: "Not comparable", russian: "Несопоставимо")
        case .noCheckpoint:
            return "—"
        }
    }
}
