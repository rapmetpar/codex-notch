import SwiftUI
import XCTest
@testable import CodexNotch

final class NotchCollapseMotionTests: XCTestCase {
    @MainActor
    func testNewOpeningAfterSettledCollapseDoesNotKeepAnOldTallCeiling() {
        let compact = CGSize(width: 212, height: 30)
        let tall = CGSize(width: 420, height: 580)
        let short = CGSize(width: 420, height: 240)
        let opened = NotchPresentationState.expanded(ExpandedContent(
            sessions: [], conversations: [], headerConversation: nil, usage: nil
        ))
        // With no hosted view SwiftUI completes synchronously. This exercises
        // a settled collapse, rather than a still-visible interrupted one.
        let model = NotchViewModel(state: opened, layoutMode: .floatingBar,
                                   compactWidth: compact.width, compactHeight: compact.height,
                                   surfaceSize: tall)
        model.update(state: .quotaCompact(nil), now: .now, layoutMode: .floatingBar,
                     compactWidth: compact.width, compactHeight: compact.height, surfaceSize: compact)
        model.update(state: opened, now: .now, layoutMode: .floatingBar,
                     compactWidth: compact.width, compactHeight: compact.height, surfaceSize: short)
        XCTAssertEqual(model.surfaceExpansionLimit, short)
        model.update(state: .quotaCompact(nil), now: .now, layoutMode: .floatingBar,
                     compactWidth: compact.width, compactHeight: compact.height, surfaceSize: compact,
                     animationsEnabled: false)
        XCTAssertNil(model.surfaceExpansionLimit, "Disabled motion must discard retained animation bounds")
    }

    @MainActor
    func testReversingAnOpeningKeepsTheSameVisibleSurfaceAtTheHandoff() {
        let compact = CGSize(width: 212, height: 30)
        let expanded = CGSize(width: 420, height: 320)
        let opened = NotchPresentationState.expanded(ExpandedContent(
            sessions: [], conversations: [], headerConversation: nil, usage: nil
        ))
        let model = NotchViewModel(state: opened, layoutMode: .floatingBar,
                                   compactWidth: compact.width, compactHeight: compact.height,
                                   surfaceSize: expanded)
        let landing = CGSize(width: 429, height: 334)
        let before = NotchAnimatedSurfaceFrame.visibleSize(
            landing, compact: compact, mode: .floatingBar, expandedLimit: model.surfaceExpansionLimit
        )
        model.update(state: .quotaCompact(nil), now: .now, layoutMode: .floatingBar,
                     compactWidth: compact.width, compactHeight: compact.height, surfaceSize: compact)
        let after = NotchAnimatedSurfaceFrame.visibleSize(
            landing, compact: compact, mode: .floatingBar, expandedLimit: model.surfaceExpansionLimit
        )
        XCTAssertEqual(after, before, "Reversing during the landing must not remove its bounds and jump outward")
    }

    @MainActor
    func testExpandedContentShrinkKeepsItsFullStartingFrameThroughClockUpdates() {
        let compact = CGSize(width: 212, height: 30)
        let tall = CGSize(width: 420, height: 580)
        let short = CGSize(width: 420, height: 320)
        let state = NotchPresentationState.expanded(ExpandedContent(
            sessions: [], conversations: [], headerConversation: nil, usage: nil
        ))
        let now = Date(timeIntervalSince1970: 1_789_200_000)
        let model = NotchViewModel(state: state, now: now, layoutMode: .floatingBar,
                                   compactWidth: compact.width, compactHeight: compact.height,
                                   surfaceSize: tall)
        model.update(state: state, now: now, layoutMode: .floatingBar,
                     compactWidth: compact.width, compactHeight: compact.height,
                     surfaceSize: short)
        model.update(state: state, now: now.addingTimeInterval(1), layoutMode: .floatingBar,
                     compactWidth: compact.width, compactHeight: compact.height,
                     surfaceSize: short)
        for height: CGFloat in [580, 500, 400, 320] {
            let proposed = CGSize(width: 420, height: height)
            XCTAssertEqual(NotchAnimatedSurfaceFrame.visibleSize(
                proposed, compact: compact, mode: .floatingBar,
                expandedLimit: model.surfaceExpansionLimit
            ), proposed, "Landing clearance must not skip the start of a content-height reduction")
        }
    }

    func testOpeningLandingStaysInsideTheCanvasForShortAndTallCards() {
        let compact = CGSize(width: 212, height: 30)
        for height: CGFloat in [200, 320, 580, 850] {
            let target = CGSize(width: 420, height: height)
            let targetFrame = CGRect(x: 750, y: 1080 - height, width: target.width, height: height)
            let canvas = NotchPresentationMotion.canvasFrame(for: targetFrame, isExpanded: true, animationsEnabled: true)
            for excess: CGFloat in [2, 8, 20, 80] {
                let visible = NotchAnimatedSurfaceFrame.visibleSize(
                    CGSize(width: target.width + excess, height: height + excess),
                    compact: compact, mode: .floatingBar, expandedLimit: target
                )
                XCTAssertGreaterThan(visible.width, target.width)
                XCTAssertGreaterThan(visible.height, target.height)
                XCTAssertLessThanOrEqual(visible.width - target.width, 6)
                XCTAssertLessThanOrEqual(visible.height - target.height, 8)
                let surface = CGRect(x: targetFrame.midX - visible.width / 2,
                                     y: targetFrame.maxY - visible.height,
                                     width: visible.width, height: visible.height)
                XCTAssertTrue(canvas.contains(surface), "The landing must never hit the native window edge")
                XCTAssertEqual(surface.maxY, targetFrame.maxY)
                XCTAssertEqual(surface.midX, targetFrame.midX)
            }
        }
    }

    func testSurfaceStartsGentlyAndSettlesWithOnlyASmallReturn() {
        // NOTCH-MOTION-009 replaces the old video-matched closing curve.
        // Keep its initial movement as a regression comparison: the shell
        // previously covered much of its travel in the first displayed frames.
        let oldClose = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.175, y: 0.885),
                                        endControlPoint: UnitPoint(x: 0.32, y: 1.1))
        let spring = NotchPresentationMotion.surfaceSpring
        let firstFrame = spring.value(target: 1.0, time: 1.0 / 60)
        XCTAssertGreaterThan(firstFrame, 0)
        XCTAssertLessThan(firstFrame, 0.06)
        XCTAssertLessThan(firstFrame, oldClose.value(at: (1.0 / 60) / 0.5) / 2)
        let frames = (0...120).map { spring.value(target: 1.0, time: Double($0) / 120) }
        let peak = frames.max()!
        XCTAssertGreaterThan(peak, 1, "Retain a subtle landing return")
        XCTAssertLessThan(peak, 1.01, "A large bounce makes the island visibly lurch")
        for (previous, next) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThan(abs(next - previous), 0.06, "No frame should jump across the travel")
        }
        XCTAssertEqual(spring.value(target: 1.0, time: 0.65), 1, accuracy: 0.002)
    }

    func testClosingStartsAtRestAndRetainsASmallFiniteReturn() {
        let firstFrame = NotchPresentationMotion.collapseCurve.value(at: (1.0 / 60) / NotchPresentationMotion.collapseDuration)
        XCTAssertGreaterThan(firstFrame, 0)
        XCTAssertLessThan(firstFrame, 0.03, "Closing should ease into travel instead of kicking at full speed")
        let frames = (0...120).map { NotchPresentationMotion.collapseCurve.value(at: Double($0) / 120) }
        XCTAssertGreaterThan(frames.max()!, 1)
        XCTAssertLessThan(frames.max()!, 1.015)
        for (previous, next) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThan(abs(next - previous), 0.04)
        }
        XCTAssertEqual(frames.last, 1)
    }

    func testFloatingReboundRemainsVisibleWithoutClippingEitherIcon() {
        for height in [NotchFloatingBarLayout.preferredHeight, NotchFloatingBarLayout.autoHiddenMenuBarHeight] {
            let compact = CGSize(width: NotchFloatingBarLayout.compactWidth, height: height)
            let start = CGSize(width: 420, height: 580)
            let frames = (0...120).map { index -> CGSize in
                let travel = NotchPresentationMotion.collapseCurve.value(at: Double(index) / 120)
                let proposed = CGSize(width: start.width + (compact.width - start.width) * travel,
                                      height: start.height + (compact.height - start.height) * travel)
                return NotchAnimatedSurfaceFrame.visibleSize(proposed, compact: compact, mode: .floatingBar)
            }
            let minimumHeight = frames.map(\.height).min()!
            let minimumWidth = frames.map(\.width).min()!
            XCTAssertLessThan(minimumHeight, compact.height)
            XCTAssertGreaterThanOrEqual(minimumHeight, compact.height * 0.94)
            XCTAssertGreaterThan(minimumHeight, (compact.height + NotchCompactLayout.indicatorDiameter) / 2 + 1)
            XCTAssertGreaterThanOrEqual(minimumWidth, compact.width * 0.992)
            XCTAssertEqual(frames.last, compact)
        }
    }

    func testPhysicalNotchCannotCompressItsCameraSafeFrameAndExpansionIsUnchanged() {
        let compact = CGSize(width: 300, height: 32)
        for proposed in [CGSize(width: 294, height: 24), CGSize(width: 280, height: 30), .zero] {
            let result = NotchAnimatedSurfaceFrame.visibleSize(proposed, compact: compact, mode: .notch)
            XCTAssertGreaterThanOrEqual(result.width, compact.width)
            XCTAssertGreaterThanOrEqual(result.height, compact.height)
        }
        for mode in [NotchLayoutMode.notch, .floatingBar] {
            for size in [compact, CGSize(width: 380, height: 180), CGSize(width: 426, height: 326)] {
                XCTAssertEqual(NotchAnimatedSurfaceFrame.visibleSize(size, compact: compact, mode: mode), size)
            }
            XCTAssertEqual(NotchAnimatedSurfaceFrame.visibleSize(CGSize(width: 180, height: 20), compact: .zero, mode: mode),
                           CGSize(width: 180, height: 20), "The hidden hover sensor must retain its own geometry")
        }
    }
}
