import AppKit
import SwiftUI

/// Lazy window creation keeps startup and the notch's canvas entirely unchanged.
final class DataHealthWindowPresenter {
    static let shared = DataHealthWindowPresenter()
    private(set) var window: NSWindow?

    func show() {
        let window = windowForPresentation(model: .shared, defaults: AppPreferences.store)
        SettingsWindowPresenter.bringToFront(window)
    }

    func windowForPresentation(model: DataHealth, defaults: UserDefaults) -> NSWindow {
        if let window { return window }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("CodexNotch.DataHealth")
        window.title = DataHealthText.title(.fromStoredValue(defaults.string(forKey: AppLanguage.storageKey)))
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.contentView = NSHostingView(rootView: DataHealthView(model: model, onTitleChange: { [weak window] title in
            // Language updates never reactivate the window or interrupt a popup.
            window?.title = title
        }).defaultAppStorage(defaults))
        window.center()
        self.window = window
        return window
    }
}
