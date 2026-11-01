import Foundation

enum FloatingCenterStyle: String, CaseIterable, Identifiable, Sendable {
    case signature
    case orbit
    case elapsed
    case flow
    case pet

    static let storageKey = "floatingCenterStyle"
    static let defaultStyle: Self = .signature
    var id: String { rawValue }

    static func fromStoredValue(_ value: String?) -> Self {
        value.flatMap(Self.init(rawValue:)) ?? defaultStyle
    }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .signature: return language.localized(chinese: "个人签名", english: "Signature", russian: "Подпись")
        case .orbit: return language.localized(chinese: "轨道签名", english: "Orbit", russian: "Орбита")
        case .elapsed: return language.localized(chinese: "运行计时", english: "Elapsed time", russian: "Таймер")
        case .pet: return language.localized(chinese: "宠物", english: "Companion", russian: "Питомец")
        case .flow: return language.localized(chinese: "细流光", english: "Light flow", russian: "Световой поток")
        }
    }

    var usesCustomText: Bool { self != .flow && self != .pet }

    func explanation(for language: AppLanguage) -> String {
        switch self {
        case .pet:
            return language.localized(chinese: "在横条中央显示所选宠物；展开后在独立空间中活动。", english: "Shows the selected companion in the center. Expand for its own stage.", russian: "Показывает выбранного питомца в центре. При раскрытии у него своя сцена.")
        case .signature:
            return language.localized(chinese: "显示自定义文字，带有柔和的流光效果。", english: "Displays custom text with a subtle shimmer.", russian: "Показывает ваш текст с мягким переливом.")
        case .orbit:
            return language.localized(chinese: "任务运行时，文字旁的圆点沿轨道旋转。", english: "A dot orbits beside the text while a task is running.", russian: "Во время работы рядом с текстом вращается точка.")
        case .elapsed:
            return language.localized(chinese: "任务运行时显示已用时间，结束后显示自定义文字。", english: "Displays elapsed time while a task is running, then custom text when it ends.", russian: "Во время работы показывает таймер, после завершения — ваш текст.")
        case .flow:
            return language.localized(chinese: "任务运行时播放流光动画，结束后停止。", english: "Displays an animated light while a task is running. The animation stops when the task ends.", russian: "Во время работы показывает световой поток, после завершения он останавливается.")
        }
    }
}

enum FloatingCenterText {
    static let storageKey = "floatingCenterText"
    static let defaultText = "Codex"
    static let maximumCharacters = 12

    static func normalized(_ text: String) -> String {
        String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(maximumCharacters))
    }

    static func displayText(_ text: String) -> String {
        let value = normalized(text)
        return value.isEmpty ? defaultText : value
    }

    static func elapsedText(activity: QuotaRingActivity, startedAt: Date?, now: Date) -> String? {
        guard activity == .running, let startedAt, startedAt > .distantPast else { return nil }
        let interval = now.timeIntervalSince(startedAt)
        guard interval.isFinite, interval < Double(Int.max) else { return nil }
        let seconds = Int(max(0, interval).rounded(.down))
        if seconds >= 3_600 {
            return "\(seconds / 3_600):" + String(format: "%02d:%02d", seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

enum FloatingCenterMotionPolicy {
    static func shouldAnimate(
        style: FloatingCenterStyle,
        activity: QuotaRingActivity,
        motionEnabled: Bool,
        isExpanded: Bool
    ) -> Bool {
        guard motionEnabled, !isExpanded else { return false }
        switch style {
        case .signature: return true
        case .orbit, .flow: return activity == .running
        case .elapsed, .pet: return false
        }
    }
}
