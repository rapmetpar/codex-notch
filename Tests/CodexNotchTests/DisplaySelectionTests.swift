import AppKit
import XCTest
import SwiftUI
@testable import CodexNotch

final class DisplaySelectionTests: XCTestCase {
    func testSelectionFallsBackAndReturnsAfterReconnectOrMirroring() {
        let builtIn = DisplaySelection.Display(identity: "built-in", drawableID: 1)
        let external = DisplaySelection.Display(identity: "external", drawableID: 2)
        let preference = "external"
        XCTAssertEqual(DisplaySelection.select(preference, displays: [builtIn, external], availableIDs: [1, 2], autoID: 1), 2)
        XCTAssertEqual(DisplaySelection.select(preference, displays: [builtIn], availableIDs: [1], autoID: 1), 1)
        XCTAssertEqual(preference, "external")
        XCTAssertEqual(DisplaySelection.select(preference, displays: [builtIn, external], availableIDs: [1, 2], autoID: 1), 2)
        let mirrored = DisplaySelection.Display(identity: "external", drawableID: 1)
        XCTAssertEqual(DisplaySelection.select(preference, displays: [builtIn, mirrored], availableIDs: [1], autoID: 1), 1)
        XCTAssertEqual(DisplaySelection.select("", displays: [builtIn, external], availableIDs: [1, 2], autoID: 1), 1)
        XCTAssertEqual(DisplaySelection.select(preference, displays: [external], availableIDs: [1], autoID: 1), 1)
    }

    func testSelectedScreenUsesFreshMetricsAndLeftOffHitArea() {
        func metrics(_ x: CGFloat, _ width: CGFloat) -> NotchScreenMetrics {
            NotchScreenMetrics(frame: NSRect(x: x, y: 0, width: width, height: 900),
                visibleFrame: NSRect(x: x, y: 0, width: width, height: 870),
                safeAreaInsets: NSEdgeInsets(), auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
        }
        let before = NotchGeometry.layout(metrics: metrics(0, 1920), leftIndicatorEnabled: false)
        let after = NotchGeometry.layout(metrics: metrics(-1440, 1440), leftIndicatorEnabled: false)
        XCTAssertEqual(after.mode, .floatingBar)
        XCTAssertEqual(after.compactFrame.midX, -720)
        XCTAssertEqual(after.frame(for: .hidden), after.visibleCompactFrame)
        XCTAssertNotEqual(before.frame(for: .hidden), after.frame(for: .hidden))
    }

    @MainActor
    func testOnePanelMovesAndRejectsStaleAnimationCompletion() throws {
        _ = NSApplication.shared
        let controller = NotchWindowController()
        controller.setRootView(Color.clear)
        let panel = try XCTUnwrap(controller.window)
        defer { controller.hideNotchPanel() }
        func layout(_ x: CGFloat) -> NotchLayout {
            let compact = NSRect(x: x, y: 1000, width: 212, height: 30)
            let expanded = NSRect(x: x - 100, y: 700, width: 412, height: 330)
            return NotchLayout(mode: .floatingBar, centerX: compact.midX,
                hoverSensorFrame: compact, compactFrame: compact,
                quotaExpandedFrame: expanded, expandedFrame: expanded, compactLeadingInset: 30)
        }
        let first = layout(-10000)
        let second = layout(-5000)
        let state = NotchPresentationState.quotaCompact(nil)
        let old = controller.prepare(layout: first, state: state, screenID: 1, screenFrame: first.compactFrame, animationsEnabled: false)
        controller.prepare(layout: second, state: state, screenID: 2, screenFrame: second.compactFrame, animationsEnabled: false)
        XCTAssertTrue(controller.window === panel)
        XCTAssertEqual(panel.frame, second.visibleCompactFrame)
        controller.finishSurfaceAnimation(identifier: old, targetFrame: first.visibleCompactFrame)
        XCTAssertEqual(panel.frame, second.visibleCompactFrame)
        controller.invalidateDisplayRoute()
        let changedMetrics = layout(-3000)
        controller.prepare(layout: changedMetrics, state: state, screenID: 2,
                           screenFrame: second.compactFrame, animationsEnabled: false)
        XCTAssertEqual(panel.frame, changedMetrics.visibleCompactFrame)
    }

    func testPreferenceIsReadFromIsolatedStore() {
        let name = "DisplaySelectionTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(NotchRuntimePreferences.read(from: defaults).selectedDisplay, "")
        defaults.set("opaque", forKey: DisplaySelection.storageKey)
        XCTAssertEqual(NotchRuntimePreferences.read(from: defaults).selectedDisplay, "opaque")
    }
}
