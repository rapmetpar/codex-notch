import AppKit
import SwiftUI

final class ReaderWindowModel: ObservableObject {
    @Published var content = ExpandedContent(sessions: [], conversations: [], headerConversation: nil, usage: nil)
    @Published var now = Date()
    var openThread: (String) -> Void = { _ in }
}

final class ReaderWindowController {
    private let model = ReaderWindowModel()
    private var window: NSWindow?

    func update(_ content: ExpandedContent, now: Date, openThread: @escaping (String) -> Void) {
        model.openThread = openThread
        if model.content != content { model.content = content }
        model.now = now
    }

    func show() {
        let window: NSWindow
        if let existing = self.window { window = existing } else {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 320, height: 300)
            window.level = .normal
            window.center()
            window.contentView = NSHostingView(rootView: ReaderWindowView(model: model).defaultAppStorage(AppPreferences.store))
            self.window = window
        }
        let language = AppLanguage.fromStoredValue(AppPreferences.store.string(forKey: AppLanguage.storageKey) ?? AppLanguage.defaultLanguage.rawValue)
        window.title = language.localized(chinese: "阅读窗口", english: "Reading Window", russian: "Окно чтения")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}
