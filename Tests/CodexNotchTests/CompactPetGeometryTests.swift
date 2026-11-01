import AppKit
import SwiftUI
import XCTest
@testable import CodexNotch

final class CompactPetGeometryTests: XCTestCase {
    private func metrics(height: CGFloat = 32, origin: CGPoint = .zero,
                         leftWidth: CGFloat = 646, notchWidth: CGFloat = 179) -> NotchScreenMetrics {
        NotchScreenMetrics(frame: CGRect(x: origin.x, y: origin.y, width: 1470, height: 956),
            visibleFrame: CGRect(x: origin.x, y: origin.y, width: 1470, height: 956 - height),
            safeAreaInsets: NSEdgeInsets(top: height, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: origin.x, y: origin.y + 956 - height, width: leftWidth, height: height),
            auxiliaryTopRightArea: CGRect(x: origin.x + leftWidth + notchWidth,
                y: origin.y + 956 - height, width: 1470 - leftWidth - notchWidth, height: height))
    }

    func testSelectedPetDoesNotEnlargeOriginalCompactSurface() {
        for height: CGFloat in [24, 32, 38] {
            let original = NotchGeometry.layout(metrics: metrics(height: height))
            let selected = NotchGeometry.layout(metrics: metrics(height: height), companionEnabled: true)
            XCTAssertEqual(selected.compactFrame, original.compactFrame)
            XCTAssertEqual(selected.visibleCompactFrame, original.visibleCompactFrame)
        }
    }

    func testOriginalCompactGeometryWeeklyCameraHeightAndExpandedBoundsStayAnchored() {
        for height: CGFloat in [24, 28, 32, 38] {
            for origin in [CGPoint.zero, CGPoint(x: -1470, y: 400)] {
                let metrics = metrics(height: height, origin: origin)
                let off = NotchGeometry.layout(metrics: metrics)
                let pet = NotchGeometry.layout(metrics: metrics, companionEnabled: true)
                XCTAssertEqual(pet.visibleCompactFrame.minX, off.compactFrame.minX)
                XCTAssertEqual(pet.visibleCompactFrame.maxX, off.compactFrame.maxX)
                XCTAssertEqual(pet.compactFrame.midX, off.compactFrame.midX)
                XCTAssertEqual(pet.compactFrame.height, height)
                XCTAssertEqual(pet.compactFrame.maxY, metrics.frame.maxY)
                XCTAssertEqual(pet.quotaExpandedFrame, off.quotaExpandedFrame)
                XCTAssertEqual(pet.expandedFrame, off.expandedFrame)
                XCTAssertEqual(pet.hoverSensorFrame, off.hoverSensorFrame)
                XCTAssertGreaterThanOrEqual(pet.visibleCompactFrame.minX, metrics.auxiliaryTopLeftArea!.minX)
                let host = NotchPanelFramePolicy.hostingFrame(canvas: pet.visibleCompactFrame, contentCenterX: pet.centerX)
                XCTAssertEqual(pet.visibleCompactFrame.minX + host.midX, pet.centerX)
            }
        }
    }

    func testSelectedCompanionOverridesIconOffButCompanionOffRestoresExactExistingCrop() {
        let metrics = metrics()
        let hiddenIcon = NotchGeometry.layout(metrics: metrics, leftIndicatorEnabled: false)
        let pet = NotchGeometry.layout(metrics: metrics, leftIndicatorEnabled: false, companionEnabled: true)
        XCTAssertGreaterThan(hiddenIcon.compactLeadingInset, 0)
        XCTAssertEqual(pet.compactLeadingInset, 0)
        let restored = NotchGeometry.layout(metrics: metrics, leftIndicatorEnabled: false, companionEnabled: false)
        XCTAssertEqual(restored, hiddenIcon)
    }

    func testUnusualHeightWidthAndFloatingFallbackDoNotMoveOriginalContent() {
        for metrics in [metrics(height: 0), metrics(height: 20), metrics(leftWidth: 30), metrics(leftWidth: 500, notchWidth: 320)] {
            let original = NotchGeometry.layout(metrics: metrics)
            let requested = NotchGeometry.layout(metrics: metrics, companionEnabled: true)
            XCTAssertEqual(requested, original, "Companion selection must retain original geometry")
        }
        let floating = NotchScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 924),
            safeAreaInsets: NSEdgeInsets(), auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
        XCTAssertEqual(NotchGeometry.layout(metrics: floating, companionEnabled: true), NotchGeometry.layout(metrics: floating))
    }

    func testOriginalSurfaceAndHitRegionReturnWithoutTrailingCompensation() {
        let layout = NotchGeometry.layout(metrics: metrics(), companionEnabled: true)
        let bounds = CGRect(origin: .zero, size: layout.compactFrame.size)
        let path = NotchSurfaceShape(layoutMode: .notch, shoulderDepth: 6, bottomRadius: 14,
            leadingInset: layout.compactLeadingInset).path(in: bounds)
        XCTAssertEqual(path.boundingRect.maxX, bounds.maxX)
        XCTAssertTrue(path.contains(CGPoint(x: bounds.maxX - 20, y: 16)))
        XCTAssertTrue(path.contains(CGPoint(x: bounds.maxX - 60, y: 16)))
    }

    @MainActor
    func testPanelSettlesToOriginalCompactAndRejectsStaleCollapseWithoutPerFrameResize() throws {
        _ = NSApplication.shared
        let controller = NotchWindowController()
        controller.setRootView(Color.clear)
        defer { controller.hideNotchPanel() }
        let layout = NotchGeometry.layout(metrics: metrics(), companionEnabled: true)
        let compact = NotchPresentationState.quotaCompact(nil)
        let expanded = NotchPresentationState.expanded(.init(sessions: [], conversations: [], headerConversation: nil, usage: nil))
        let panel = try XCTUnwrap(controller.window)
        controller.prepare(layout: layout, state: compact, animationsEnabled: false)
        XCTAssertEqual(panel.frame, layout.visibleCompactFrame)
        let hosting = try XCTUnwrap(panel.contentView?.subviews.first)
        XCTAssertEqual(panel.frame.minX + hosting.frame.midX, layout.centerX, accuracy: 0.01)
        let opening = controller.prepare(layout: layout, state: expanded)
        controller.finishSurfaceAnimation(identifier: opening, targetFrame: layout.frame(for: expanded))
        let closing = controller.prepare(layout: layout, state: compact)
        controller.settleFrame(layout: layout, state: compact, animationWillComplete: true)
        let reopened = controller.prepare(layout: layout, state: expanded)
        let canvas = panel.frame
        controller.finishSurfaceAnimation(identifier: closing, targetFrame: layout.visibleCompactFrame)
        XCTAssertEqual(panel.frame, canvas)
        controller.finishSurfaceAnimation(identifier: reopened, targetFrame: layout.frame(for: expanded))
        controller.prepare(layout: layout, state: compact, animationsEnabled: false)
        controller.settleFrame(layout: layout, state: compact, animationsEnabled: false)
        XCTAssertEqual(panel.frame, layout.visibleCompactFrame, "Expanded canvas must stop intercepting the menu bar")
        XCTAssertEqual(panel.frame.minX + hosting.frame.midX, layout.centerX, accuracy: 0.01)
    }
}
