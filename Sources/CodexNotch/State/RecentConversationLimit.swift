import Foundation

enum RecentConversationLimit: Int, CaseIterable, Identifiable, Sendable {
    case none = 0
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7
    case eight = 8
    case nine = 9
    case ten = 10
    case eleven = 11
    case twelve = 12
    case thirteen = 13
    case fourteen = 14
    case fifteen = 15
    case sixteen = 16
    case seventeen = 17
    case eighteen = 18
    case nineteen = 19
    case twenty = 20

    static let maximumCount = RecentConversationLimit.twenty.rawValue

    static let storageKey = "recentConversationLimit"
    static let defaultLimit: RecentConversationLimit = .two

    var id: Int { rawValue }

    var title: String {
        title(for: .chinese)
    }

    func title(for language: AppLanguage) -> String {
        language.localized(
            chinese: "\(rawValue) 条",
            english: rawValue == 1 ? "1 conversation" : "\(rawValue) conversations",
            russian: russianConversationCount
        )
    }

    private var russianConversationCount: String {
        let suffix: String
        if (11...14).contains(rawValue % 100) {
            suffix = "чатов"
        } else {
            switch rawValue % 10 {
            case 1: suffix = "чат"
            case 2...4: suffix = "чата"
            default: suffix = "чатов"
            }
        }
        return "\(rawValue) \(suffix)"
    }

    static func fromStoredValue(_ rawValue: Int) -> RecentConversationLimit {
        Self(rawValue: rawValue) ?? Self.defaultLimit
    }
}

struct NotchRuntimePreferences: Equatable, Sendable {
    let recentConversationLimit: RecentConversationLimit
    let language: AppLanguage
    let animationsEnabled: Bool
    let notchDisplayEnabled: Bool
    var leftIndicatorEnabled: Bool = true
    var petLibraryRevision: Int = 0
    var conversationCategoryOrder: ConversationCategoryOrder = .defaultOrder

    var conversationProjectOrder = ConversationProjectOrder()
    var activationMode: NotchActivationMode = .hover

    static func read(from userDefaults: UserDefaults) -> NotchRuntimePreferences {
        let recentConversationLimit = (userDefaults.object(
            forKey: RecentConversationLimit.storageKey
        ) as? NSNumber).map { $0.intValue } ?? RecentConversationLimit.defaultLimit.rawValue

        return NotchRuntimePreferences(
            recentConversationLimit: RecentConversationLimit.fromStoredValue(recentConversationLimit),
            language: AppLanguage.fromStoredValue(
                userDefaults.string(forKey: AppLanguage.storageKey)
            ),
            animationsEnabled: AppAnimationPreference.isEnabled(in: userDefaults),
            notchDisplayEnabled: NotchDisplayPreference.isEnabled(in: userDefaults),
            leftIndicatorEnabled: StatusIconStyle.fromStoredValue(
                userDefaults.string(forKey: StatusIconStyle.storageKey)
            ).showsLeftIndicator,
            petLibraryRevision: userDefaults.integer(forKey: PetCompanionController.revisionKey),
            conversationCategoryOrder: ConversationCategoryOrder.fromStoredValue(
                userDefaults.string(forKey: ConversationCategoryOrder.storageKey)
            ),
            conversationProjectOrder: .read(from: userDefaults),
            activationMode: .read(from: userDefaults)
        )
    }
}
