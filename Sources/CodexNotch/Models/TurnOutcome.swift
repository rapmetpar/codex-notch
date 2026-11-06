import Foundation

/// Only lifecycle metadata; a terminal event does not assess answer quality.
enum TurnOutcome: Hashable, Sendable {
    case completedEvent, interrupted, unknown

    func label(language: AppLanguage) -> String {
        switch self {
        case .completedEvent: return language.localized(chinese: "已结束", english: "Ended", russian: "Завершён")
        case .interrupted: return language.localized(chinese: "已中断", english: "Interrupted", russian: "Прерван")
        case .unknown: return language.localized(chinese: "状态未知", english: "Outcome unknown", russian: "Исход неизвестен")
        }
    }

    func explanation(language: AppLanguage) -> String {
        switch self {
        case .completedEvent: return language.localized(chinese: "收到结束事件；这不代表任务成功", english: "A completion event was received; this does not establish task success", russian: "Получено событие завершения; это не подтверждает успех задачи")
        case .interrupted: return language.localized(chinese: "运行被明确中断", english: "The turn was explicitly interrupted", russian: "Запуск был явно прерван")
        case .unknown: return language.localized(chinese: "终止信息不足，无法确认结果", english: "Terminal metadata is insufficient to identify the outcome", russian: "Недостаточно данных о завершении, чтобы определить исход")
        }
    }
}
