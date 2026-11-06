import Foundation

/// Presentation-only redaction. IDs remain local and are never rendered.
struct PresentationPrivacyPolicy {
    static let storageKey = "presentationPrivacy.enabled"
    let enabled: Bool

    func statusIconStyle(_ original: StatusIconStyle) -> StatusIconStyle {
        enabled && original == .custom ? .codex : original
    }

    func navigate(confirm: () -> Bool, action: () -> Void) {
        guard !enabled || confirm() else { return }
        action()
    }

    func chat(_ index: Int, language: AppLanguage) -> String {
        language.localized(chinese: "对话 \(index)", english: "Chat \(index)", russian: "Чат \(index)")
    }

    func project(_ index: Int, language: AppLanguage) -> String {
        language.localized(chinese: "项目 \(index)", english: "Project \(index)", russian: "Проект \(index)")
    }
}

/// Opaque identifiers stay in memory only. Assign each visible item one alias
/// for the lifetime of the process, independent of list reordering or surface.
final class PresentationAliases {
    static let shared = PresentationAliases()
    private let lock = NSLock()
    private var chats: [String: Int] = [:]
    private var projects: [String: Int] = [:]

    func chat(_ id: String, language: AppLanguage) -> String {
        lock.lock(); defer { lock.unlock() }
        let number = chats[id] ?? (chats.count + 1)
        chats[id] = number
        return PresentationPrivacyPolicy(enabled: true).chat(number, language: language)
    }

    func project(_ id: String, language: AppLanguage) -> String {
        lock.lock(); defer { lock.unlock() }
        let number = projects[id] ?? (projects.count + 1)
        projects[id] = number
        return PresentationPrivacyPolicy(enabled: true).project(number, language: language)
    }
}
