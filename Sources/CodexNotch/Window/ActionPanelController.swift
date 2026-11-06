import AppKit
import SwiftUI

private final class ActionKeyPanel: NSPanel {
    var handleKey: ((UInt16) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
           handleKey?(event.keyCode) == true { return }
        super.sendEvent(event)
    }
}

/// An explicitly requested, independent key window; the notch remains non-key.
final class ActionPanelController: NSWindowController, NSWindowDelegate {
    private var previousApp: NSRunningApplication?
    private let model = ActionPanelModel()
    var onOpenThread: ((String) -> Void)?

    init() {
        let panel = ActionKeyPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "CodexNotch"
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.delegate = self
        panel.handleKey = { [weak self] key in self?.handleKey(key) ?? false }
        panel.contentView = NSHostingView(rootView: ActionPanelView(model: model,
            openThread: { [weak self] id in self?.open(id) },
            dismiss: { [weak self] in self?.dismiss() }))
        panel.center()
    }

    required init?(coder: NSCoder) { nil }

    func present(content: ExpandedContent, language: AppLanguage, previousApp: NSRunningApplication?) {
        guard let window else { return }
        if !window.isVisible {
            self.previousApp = previousApp
            model.selectedID = content.conversations.first?.threadID
        }
        model.update(content: content, language: language)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func update(content: ExpandedContent, language: AppLanguage) {
        guard window?.isVisible == true else { return }
        model.update(content: content, language: language)
    }

    func dismiss() {
        window?.orderOut(nil)
        previousApp?.activate(options: [])
        previousApp = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
    }

    private func handleKey(_ key: UInt16) -> Bool {
        switch key {
        case 53:
            dismiss()
            return true
        case 125, 126:
            model.selectedID = model.adjacentID(to: model.selectedID, forward: key == 125)
            return model.selectedID != nil
        case 36, 76:
            guard let id = model.selectedID,
                  model.conversations.contains(where: { $0.threadID == id }) else { return false }
            open(id)
            return true
        default:
            return false
        }
    }

    private func open(_ id: String) {
        window?.orderOut(nil)
        previousApp = nil
        onOpenThread?(id)
    }
}
