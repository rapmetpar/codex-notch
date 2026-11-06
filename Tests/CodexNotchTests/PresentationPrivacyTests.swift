import AppKit
import ApplicationServices
import SwiftUI
import XCTest
@testable import CodexNotch

final class PresentationPrivacyTests: XCTestCase {
    @MainActor
    func testProjectControlsUseRedactedAccessibilityAndRestoreOriginal() throws {
        _ = NSApplication.shared
        let suite = "PresentationPrivacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = SessionActivity(threadID: "synthetic", turnID: "turn", title: "CANARY_CHAT", cwd: "/synthetic/CANARY_PROJECT", originator: nil, startedAt: now, lastActivityAt: now)
        let row = ConversationSummary(session: session, activity: .running(startedAt: now))
        let content = ExpandedContent(sessions: [session], conversations: [row], headerConversation: nil, usage: nil)
        func buttons(_ view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
        }
        for enabled in [true, false] {
            defaults.set(enabled, forKey: PresentationPrivacyPolicy.storageKey)
            let view = ProjectConversationListView(content: content, now: now, language: .english,
                onOpenThread: { _ in }, onDropProjects: { _, _ in false }, onMoveProject: { _, _ in })
                .defaultAppStorage(defaults).frame(width: 392)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 392, height: 100)
            host.layoutSubtreeIfNeeded()
            let labels = buttons(host).compactMap { $0.accessibilityLabel() } + buttons(host).compactMap { $0.toolTip }
            XCTAssertFalse(labels.isEmpty)
            if enabled {
                XCTAssertTrue(labels.contains { $0.contains("Project 1") })
                XCTAssertFalse(labels.contains { $0.contains("CANARY_PROJECT") })
            } else {
                XCTAssertTrue(labels.contains { $0.contains("CANARY_PROJECT") })
            }
        }
    }

    @MainActor
    func testFallbackMenuRedactsEveryConversationAndRestoresOriginal() throws {
        _ = NSApplication.shared
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = SessionActivity(threadID: "menu-a", turnID: "a", title: "CANARY_CHAT", cwd: "/sample/CANARY_PROJECT", originator: nil, startedAt: now, lastActivityAt: now)
        let row = ConversationSummary(session: first, activity: .running(startedAt: now))
        let content = ExpandedContent(sessions: [first], conversations: [row], headerConversation: row, usage: nil)
        let layout = NotchLayout(mode: .menuBarFallback, centerX: 0, hoverSensorFrame: .zero,
            compactFrame: .zero, quotaExpandedFrame: .zero, expandedFrame: .zero)
        let controller = NotchWindowController()
        defer { controller.close() }
        for state in [NotchPresentationState.workingCompact(primary: first, count: 1, usage: nil),
                      .completedCompact(first, usage: nil), .expanded(content)] {
            controller.privacyEnabled = true
            controller.prepare(layout: layout, state: state)
            let safe = try XCTUnwrap(controller.fallbackMenu).items.map(\.title).joined(separator: " ")
            XCTAssertFalse(safe.contains("CANARY"), "Fallback menu leaked private metadata")
            controller.privacyEnabled = false
            controller.prepare(layout: layout, state: state)
            let original = try XCTUnwrap(controller.fallbackMenu).items.map(\.title).joined(separator: " ")
            XCTAssertTrue(original.contains("CANARY"), "Original menu content should return")
        }
    }

    @MainActor
    func testConversationRowAccessibilityAndTooltipUseTheProjectedLabels() throws {
        _ = NSApplication.shared
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = SessionActivity(threadID: "ax-canary", turnID: "turn", title: "CANARY_CHAT", cwd: "/x/CANARY_PROJECT", originator: nil, startedAt: now, lastActivityAt: now)
        let row = ConversationSummary(session: task, activity: .running(startedAt: now))
        let view = ConversationRowView(conversation: row, now: now, language: .english,
            privacyTitle: "Chat 1", privacyProject: "Project 1", action: {})
        let host = NSHostingView(rootView: view.frame(width: 392, height: 40))
        let panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 392, height: 40))
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 392, height: 40)
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.contentView = nil }
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        var strings: [String] = []
        func collect(_ node: AXUIElement, depth: Int) {
            guard depth < 12 else { return }
            for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(node, attribute as CFString, &value) == .success,
                   let value = value as? String { strings.append(value) }
            }
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &value) == .success,
               let children = value as? [AXUIElement] {
                children.forEach { collect($0, depth: depth + 1) }
            }
        }
        collect(AXUIElementCreateApplication(getpid()), depth: 0)
        guard !strings.isEmpty else { throw XCTSkip("System AX did not expose this synthetic test process; manual VoiceOver verification remains required") }
        XCTAssertTrue(strings.contains { $0.contains("Chat 1") }, "Expected the hosted row's actual accessibility label; observed: \(strings)")
        XCTAssertFalse(strings.contains { $0.contains("CANARY") }, "Accessibility and tooltip must not expose original metadata")
    }

    @MainActor
    func testFloatingSignaturePixelsAreHiddenAndRestored() throws {
        _ = NSApplication.shared
        let suite = "PresentationPrivacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("CANARY", forKey: FloatingCenterText.storageKey)
        defaults.set(FloatingCenterStyle.signature.rawValue, forKey: FloatingCenterStyle.storageKey)
        func snapshot(_ enabled: Bool) throws -> Data {
            defaults.set(enabled, forKey: PresentationPrivacyPolicy.storageKey)
            let view = FloatingCenterView(activity: .idle, startedAt: nil, now: .distantPast, isExpanded: false)
                .defaultAppStorage(defaults).environment(\.notchMotionEnabled, false)
            let bitmap = try hostedViewSnapshot(view, size: NSSize(width: 180, height: 32))
            return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        }
        let original = try snapshot(false)
        let masked = try snapshot(true)
        XCTAssertNotEqual(original, masked)
        defaults.set("OTHER PRIVATE", forKey: FloatingCenterText.storageKey)
        XCTAssertEqual(try snapshot(true), masked, "Private text cannot change masked pixels")
        defaults.set("CANARY", forKey: FloatingCenterText.storageKey)
        XCTAssertEqual(try snapshot(false), original, "Turning privacy off restores the exact signature")
    }

    @MainActor
    func testCustomStatusPixelsAreHiddenWithoutChangingChoicesOrActivity() throws {
        _ = NSApplication.shared
        let suite = "PresentationPrivacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let companion = PetCompanionController(store: PetLibraryStore(rootURL: temp), defaults: defaults, loadImmediately: false)
        func image(_ color: NSColor) throws -> Data {
            let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            for y in 0..<16 { for x in 0..<16 { rep.setColor(color, atX: x, y: y) } }
            return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        }
        let red = try image(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))
        let blue = try image(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1))
        defaults.set(StatusIconStyle.custom.rawValue, forKey: StatusIconStyle.storageKey)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = SessionActivity(threadID: "pixels", turnID: "turn", title: "CANARY", cwd: "/synthetic/secret", originator: nil, startedAt: now, lastActivityAt: now)
        let state = NotchPresentationState.workingCompact(primary: task, count: 1, usage: nil)
        let model = NotchViewModel(state: state, now: now, layoutMode: .notch,
            cameraSafeAreaInset: 32, compactWidth: 257, compactHeight: 32,
            surfaceSize: NSSize(width: 257, height: 32), animationsEnabled: false)
        func snapshot(privacy: Bool, artwork: Data) throws -> Data {
            defaults.set(privacy, forKey: PresentationPrivacyPolicy.storageKey)
            defaults.set(artwork, forKey: CustomStatusIcon.storageKey)
            let view = NotchView(model: model, companion: companion).defaultAppStorage(defaults)
            let rep = try hostedViewSnapshot(view, size: NSSize(width: 257, height: 32))
            return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        }
        let hiddenRed = try snapshot(privacy: true, artwork: red)
        XCTAssertEqual(try snapshot(privacy: true, artwork: blue), hiddenRed, "Private pixels must not affect the masked island")
        let shownBlue = try snapshot(privacy: false, artwork: blue)
        XCTAssertNotEqual(shownBlue, hiddenRed)
        XCTAssertEqual(defaults.data(forKey: CustomStatusIcon.storageKey), blue)
        XCTAssertEqual(defaults.string(forKey: StatusIconStyle.storageKey), StatusIconStyle.custom.rawValue)
        XCTAssertEqual(model.state, state)
    }

    func testPrivacyReplacesOnlyCustomArtworkAndKeepsOtherIconChoices() {
        let policy = PresentationPrivacyPolicy(enabled: true)
        XCTAssertEqual(policy.statusIconStyle(.custom), .codex)
        XCTAssertEqual(policy.statusIconStyle(.off), .off)
        XCTAssertEqual(policy.statusIconStyle(.chatGPT), .chatGPT)
        XCTAssertEqual(PresentationPrivacyPolicy(enabled: false).statusIconStyle(.custom), .custom)
    }

    func testAliasesStayStableAcrossReorderingAndLanguages() {
        let aliases = PresentationAliases()
        XCTAssertEqual(aliases.chat("a", language: .english), "Chat 1")
        XCTAssertEqual(aliases.chat("b", language: .english), "Chat 2")
        XCTAssertEqual(aliases.chat("a", language: .russian), "Чат 1")
        XCTAssertEqual(aliases.project("p", language: .english), "Project 1")
        XCTAssertEqual(aliases.project("q", language: .english), "Project 2")
        XCTAssertEqual(aliases.project("p", language: .russian), "Проект 1")
    }

    func testNavigationRequiresSeparateConfirmationAndCancelDoesNothing() {
        var opened = 0
        var prompts = 0
        let curtain = PresentationPrivacyPolicy(enabled: true)
        curtain.navigate(confirm: { prompts += 1; return false }, action: { opened += 1 })
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(opened, 0)
        curtain.navigate(confirm: { prompts += 1; return true }, action: { opened += 1 })
        XCTAssertEqual(opened, 1)
        PresentationPrivacyPolicy(enabled: false).navigate(confirm: { XCTFail("Unexpected prompt"); return false }, action: { opened += 1 })
        XCTAssertEqual(opened, 2)
    }

    func testPreferenceDefaultsOffAndPersistsWithoutChangingAppearance() throws {
        let suite = "PresentationPrivacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("CANARY_SIGNATURE", forKey: FloatingCenterText.storageKey)
        XCTAssertFalse(defaults.bool(forKey: PresentationPrivacyPolicy.storageKey))
        defaults.set(true, forKey: PresentationPrivacyPolicy.storageKey)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertTrue(reopened.bool(forKey: PresentationPrivacyPolicy.storageKey))
        XCTAssertEqual(reopened.string(forKey: FloatingCenterText.storageKey), "CANARY_SIGNATURE")
        reopened.set(false, forKey: PresentationPrivacyPolicy.storageKey)
        XCTAssertEqual(reopened.string(forKey: FloatingCenterText.storageKey), "CANARY_SIGNATURE")
    }
}
