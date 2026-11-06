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
                Button(appLanguage.localized(chinese: "阅读窗口…", english: "Reading Window…", russian: "Окно чтения…")) {
                    appDelegate.showReaderWindow()
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
