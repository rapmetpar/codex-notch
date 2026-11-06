import SwiftUI

@main
struct CodexNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppLanguage.storageKey, store: AppPreferences.store)
    private var appLanguageRaw = AppLanguage.defaultLanguage.rawValue

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
                Button(appLanguage.localized(chinese: "配额检查点…", english: "Quota Checkpoint…", russian: "Контрольная точка квоты…")) {
                    appDelegate.showQuotaCheckpoint()
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
