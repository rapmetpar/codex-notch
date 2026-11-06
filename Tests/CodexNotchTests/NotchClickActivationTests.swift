import AppKit
import SwiftUI
import XCTest
@testable import CodexNotch

final class NotchClickActivationTests: XCTestCase {
    func testOptInPreferenceDefaultsToHoverAndRejectsUnknownValues() throws {
        let suite = "NotchClickActivationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(NotchRuntimePreferences.read(from: defaults).activationMode, .hover)
        defaults.set("unknown", forKey: NotchActivationMode.storageKey)
        XCTAssertEqual(NotchRuntimePreferences.read(from: defaults).activationMode, .hover)
        defaults.set("click", forKey: NotchActivationMode.storageKey)
        XCTAssertEqual(NotchRuntimePreferences.read(from: defaults).activationMode, .click)
    }

    func testToggleDismissAndReopen() {
        var state = NotchClickActivation()
        XCTAssertFalse(state.isOpen)
        state.send(.pointerMoved)
        XCTAssertFalse(state.isOpen)
        state.send(.toggle)
        XCTAssertTrue(state.isOpen)
        state.send(.pointerMoved)
        XCTAssertTrue(state.isOpen)
        state.send(.dismiss)
        state.send(.dismiss)
        XCTAssertFalse(state.isOpen)
        state.send(.toggle)
        XCTAssertTrue(state.isOpen)
        state.send(.toggle)
        XCTAssertFalse(state.isOpen)
    }

    @MainActor
    func testEscapeOnlyDismissesWhenDisclosureAcceptsKeys() throws {
        _ = NSApplication.shared
        let panel = NotchPanel(contentRect: NSRect(x: -10000, y: 0, width: 100, height: 30))
        var dismissed = 0
        panel.onEscape = { dismissed += 1 }
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        XCTAssertFalse(panel.canBecomeKey)
        panel.acceptsDisclosureKeys = true
        XCTAssertTrue(panel.canBecomeKey)
        panel.keyDown(with: escape)
        XCTAssertEqual(dismissed, 1)
        panel.acceptsDisclosureKeys = false
        XCTAssertFalse(panel.canBecomeKey)
    }
}

extension NotchClickActivationTests {
    @MainActor
    func testOutsideClickUsesProductionWindowAndReclaimsCompactFrame() throws {
        _ = NSApplication.shared
        let controller = NotchWindowController()
        let panel = try XCTUnwrap(controller.window as? NotchPanel)
        defer { controller.setClickDisclosureOpen(false, onDismiss: {}); controller.hideNotchPanel() }
        let compact = NSRect(x: -10000, y: 1000, width: 212, height: 30)
        let expanded = NSRect(x: -10104, y: 750, width: 420, height: 280)
        let layout = NotchLayout(mode: .floatingBar, centerX: compact.midX, hoverSensorFrame: compact,
                                 compactFrame: compact, quotaExpandedFrame: expanded, expandedFrame: expanded)
        let closed = NotchPresentationState.quotaCompact(nil)
        let opened = NotchPresentationState.expanded(ExpandedContent(sessions: [], conversations: [], headerConversation: nil, usage: nil))
        controller.prepare(layout: layout, state: opened, animationsEnabled: false)
        var dismissed = 0
        controller.setClickDisclosureOpen(true) {
            dismissed += 1
            controller.setClickDisclosureOpen(false, onDismiss: {})
            controller.prepare(layout: layout, state: closed, animationsEnabled: false)
            controller.settleFrame(layout: layout, state: closed, animationsEnabled: false)
        }
        controller.handleClickDisclosureMouseDown(at: NSPoint(x: expanded.midX, y: expanded.midY))
        XCTAssertEqual(dismissed, 0)
        controller.handleClickDisclosureMouseDown(at: NSPoint(x: expanded.maxX + 1, y: expanded.midY))
        XCTAssertEqual(dismissed, 1)
        XCTAssertEqual(panel.frame, compact)
        XCTAssertFalse(panel.canBecomeKey)
        controller.handleClickDisclosureMouseDown(at: .zero)
        XCTAssertEqual(dismissed, 1)
    }
}

extension NotchClickActivationTests {
    @MainActor
    func testCompactButtonRoutesClickModeToDisclosureAndDefaultToCodex() throws {
        _ = NSApplication.shared
        let suite = "NotchClickButton.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("en", forKey: AppLanguage.storageKey)
        for mode in [NotchActivationMode.hover, .click] {
            defaults.set(mode.rawValue, forKey: NotchActivationMode.storageKey)
            var activations = 0
            var disclosures = 0
            var openings = 0
            let model = NotchViewModel(state: .quotaCompact(nil), layoutMode: .floatingBar,
                compactWidth: 212, compactHeight: 30, surfaceSize: CGSize(width: 212, height: 30),
                animationsEnabled: false, onOpenThread: { _ in openings += 1 },
                onActivateChatGPT: { activations += 1 })
            model.onToggleDisclosure = { disclosures += 1 }
            let host = NSHostingView(rootView: NotchView(model: model).defaultAppStorage(defaults))
            host.sizingOptions = []
            let panel = NotchPanel(contentRect: NSRect(x: -10000, y: 1000, width: 212, height: 30))
            panel.isReleasedWhenClosed = false
            panel.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 212, height: 30)
            panel.orderFrontRegardless()
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 106, y: 15),
                    modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
                panel.sendEvent(event)
            }
            XCTAssertEqual(disclosures, mode == .click ? 1 : 0)
            XCTAssertEqual(activations, mode == .hover ? 1 : 0)
            XCTAssertEqual(openings, 0)
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }
}
