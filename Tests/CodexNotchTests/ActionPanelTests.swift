import AppKit
import XCTest
@testable import CodexNotch

final class ActionPanelTests: XCTestCase {
    private func content(_ count: Int) -> ExpandedContent {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = (0..<count).map { i in
            let session = SessionActivity(threadID: "synthetic-\(i)", turnID: "turn", title: "Chat \(i)", cwd: nil,
                originator: nil, startedAt: now, lastActivityAt: now)
            return ConversationSummary(session: session, activity: .running(startedAt: now))
        }
        return ExpandedContent(sessions: [], conversations: rows, headerConversation: rows.first, usage: nil)
    }

    func testTraversalReachesEveryThreadAndTracksIdentityAfterReordering() {
        let model = ActionPanelModel()
        let original = content(20)
        model.update(content: original, language: .english)
        var focus: String?
        var visited: [String] = []
        for _ in 0..<20 {
            focus = model.adjacentID(to: focus, forward: true)
            visited.append(focus!)
        }
        XCTAssertEqual(visited, original.conversations.map(\.threadID))
        let reversed = ExpandedContent(sessions: [], conversations: Array(original.conversations.reversed()), headerConversation: nil, usage: nil)
        model.update(content: reversed, language: .russian)
        XCTAssertEqual(focus, "synthetic-19")
        XCTAssertEqual(model.adjacentID(to: focus, forward: true), "synthetic-18")
        model.update(content: original.limitingRecentConversations(to: .none), language: .chinese)
        XCTAssertNil(model.adjacentID(to: focus, forward: true))
    }

    func testShortcutRegistrationFailureLeavesToggleAvailable() {
        let toggle = ActionShortcutToggle()
        var failures = 0
        toggle.toggle(register: { nil }, unavailable: { failures += 1 })
        XCTAssertEqual(failures, 1)
        XCTAssertFalse(toggle.isEnabled)
        toggle.toggle(register: { NSObject() }, unavailable: { XCTFail("unexpected failure") })
        XCTAssertTrue(toggle.isEnabled)
        toggle.toggle(register: { XCTFail("should unregister"); return nil }, unavailable: { XCTFail("unexpected failure") })
        XCTAssertFalse(toggle.isEnabled)
    }

    @MainActor
    func testNativePanelEnterOpensFocusedThread() throws {
        _ = NSApplication.shared
        let panel = ActionPanelController()
        var opened: [String] = []
        panel.onOpenThread = { opened.append($0) }
        panel.present(content: content(20), language: .english, previousApp: nil)
        defer { panel.dismiss() }
        let window = try XCTUnwrap(panel.window)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36))
        window.sendEvent(enter)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(opened, ["synthetic-0"])
    }

    @MainActor
    func testNativeArrowsReachLastThreadAndEscapeDoesNotOpen() throws {
        _ = NSApplication.shared
        let panel = ActionPanelController()
        var opened: [String] = []
        panel.onOpenThread = { opened.append($0) }
        panel.present(content: content(20), language: .english, previousApp: nil)
        defer { panel.dismiss() }
        let window = try XCTUnwrap(panel.window)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        func send(_ key: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) throws {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: chars, charactersIgnoringModifiers: chars,
                isARepeat: false, keyCode: key))
            window.sendEvent(event)
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        for _ in 0..<19 { try send(125, "\u{f701}", [.numericPad, .function]) }
        try send(36, "\r")
        XCTAssertEqual(opened, ["synthetic-19"])
        opened.removeAll()
        panel.present(content: content(20), language: .english, previousApp: nil)
        try send(53, "\u{1b}")
        XCTAssertTrue(opened.isEmpty)
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    func testDismissDoesNotNavigate() {
        _ = NSApplication.shared
        let panel = ActionPanelController()
        var opened: [String] = []
        panel.onOpenThread = { opened.append($0) }
        panel.present(content: content(20), language: .english, previousApp: nil)
        panel.update(content: content(0), language: .russian)
        panel.dismiss()
        XCTAssertTrue(opened.isEmpty)
    }
}
