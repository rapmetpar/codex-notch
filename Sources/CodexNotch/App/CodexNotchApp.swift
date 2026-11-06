import SwiftUI

extension Notification.Name {
    static let enableActionShortcut = Notification.Name("CodexNotch.enableActionShortcut")
    static let openActionPanel = Notification.Name("CodexNotch.openActionPanel")
}

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
            CommandGroup(after: .appInfo) {
                Button(appLanguage.localized(chinese: "切换操作快捷键 ⇧⌥⌘A", english: "Toggle Actions Shortcut ⇧⌥⌘A", russian: "Переключить сочетание ⇧⌥⌘A")) {
                    NotificationCenter.default.post(name: .enableActionShortcut, object: nil)
                }
                Button(appLanguage.localized(chinese: "打开操作…", english: "Open Actions…", russian: "Открыть действия…")) {
                    NotificationCenter.default.post(name: .openActionPanel, object: nil)
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
