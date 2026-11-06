import SwiftUI

@main
struct CodexNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppLanguage.storageKey, store: AppPreferences.store)
    private var appLanguageRaw = AppLanguage.defaultLanguage.rawValue

    @AppStorage(RecentConversationLimit.storageKey, store: AppPreferences.store)
    private var recentLimit = RecentConversationLimit.defaultLimit.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage.fromStoredValue(appLanguageRaw)
    }

    var body: some Scene {
        Settings {
            NotchSettingsView()
                .defaultAppStorage(AppPreferences.store)
        }
        .commands {
            CommandGroup(after: .appSettings) {
                if RecentConversationLimit.fromStoredValue(recentLimit) != .none {
                    Button(appLanguage.localized(chinese: "搜索最近对话…", english: "Search recent conversations…", russian: "Поиск недавних чатов…")) {
                        NotificationCenter.default.post(name: .openConversationSearch, object: nil)
                    }
                }
            }
            CommandGroup(replacing: .appSettings) {
                NotchSettingsButton {
                    Text(appLanguage.localized(chinese: "设置…", english: "Settings…", russian: "Настройки…"))
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let openConversationSearch = Notification.Name("CodexNotch.openConversationSearch")
}
