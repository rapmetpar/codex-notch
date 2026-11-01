import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"
    case russian = "ru"

    static let storageKey = "appLanguage"
    static let defaultLanguage: AppLanguage = .english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        case .russian:
            return "Русский"
        }
    }

    // Require every supported translation so new UI copy cannot silently
    // fall back to another language.
    func localized(chinese: String, english: String, russian: String) -> String {
        switch self {
        case .chinese: return chinese
        case .english: return english
        case .russian: return russian
        }
    }

    static func fromStoredValue(_ rawValue: String?) -> AppLanguage {
        guard let rawValue else { return defaultLanguage }
        return Self(rawValue: rawValue) ?? defaultLanguage
    }
}
