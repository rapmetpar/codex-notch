import AppKit
import QuartzCore
import SwiftUI
import XCTest
@testable import CodexNotch

final class ConversationStatusTests: XCTestCase {
    @MainActor
    private func shapes(_ view: ConversationStatusLayerView) throws -> [CAShapeLayer] {
        let layers = try XCTUnwrap(view.layer?.sublayers?.compactMap { $0 as? CAShapeLayer })
        XCTAssertEqual(layers.count, 2)
        return layers
    }

    @MainActor
    func testMotionOffKeepsDistinctRunningAndCompletedSymbols() throws {
        let view = ConversationStatusLayerView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        view.layout()
        let layers = try shapes(view)
        view.configure(isRunning: true, motionEnabled: false)
        XCTAssertEqual(layers[0].strokeEnd, 0.72, accuracy: 0.001)
        XCTAssertTrue(layers[1].isHidden)
        let runningColor = layers[0].strokeColor
        view.configure(isRunning: false, motionEnabled: false)
        XCTAssertEqual(layers[0].strokeEnd, 1)
        XCTAssertFalse(layers[1].isHidden)
        XCTAssertNotEqual(layers[0].strokeColor, runningColor)
        XCTAssertFalse(view.animationIsRequested)
        XCTAssertTrue(layers.allSatisfy { $0.animationKeys()?.isEmpty ?? true })
        for shape in layers {
            let extent = try XCTUnwrap(shape.path).boundingBoxOfPath.insetBy(
                dx: -shape.lineWidth / 2, dy: -shape.lineWidth / 2
            )
            XCTAssertTrue(shape.bounds.contains(extent))
        }
    }

    @MainActor
    func testDetachedAndPreviouslyCompletedRowsDoNotReplayCompletion() throws {
        let view = ConversationStatusLayerView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        let layers = try shapes(view)
        view.configure(isRunning: true, motionEnabled: true)
        XCTAssertFalse(view.layerAnimationIsRunning)
        XCTAssertTrue(layers.allSatisfy { $0.animationKeys()?.isEmpty ?? true })
        view.configure(isRunning: false, motionEnabled: true)
        view.startLayerAnimation()
        XCTAssertFalse(view.animationIsRequested)
        XCTAssertTrue(layers.allSatisfy { $0.animationKeys()?.isEmpty ?? true })
    }

    @MainActor
    func testEachVisibleChatStopsAndRevealsCompletionIndependently() async throws {
        _ = NSApplication.shared
        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 60, height: 30))
        let first = ConversationStatusLayerView(frame: NSRect(x: 4, y: 7, width: 16, height: 16))
        let second = ConversationStatusLayerView(frame: NSRect(x: 35, y: 7, width: 16, height: 16))
        canvas.addSubview(first)
        canvas.addSubview(second)
        let panel = NotchPanel(contentRect: canvas.frame)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        for _ in 0..<20 {
            while let event = NSApp.nextEvent(matching: .any, until: .distantPast,
                                             inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            NSApp.updateWindows()
            CATransaction.flush()
            if panel.occlusionState.contains(.visible) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(panel.occlusionState.contains(.visible))
        for view in [first, second] {
            view.layout()
            view.configure(isRunning: true, motionEnabled: true)
        }
        let firstLayers = try shapes(first)
        let secondLayers = try shapes(second)
        let spin = try XCTUnwrap(firstLayers[0].animation(forKey: "conversation.running"))
        XCTAssertEqual(spin.repeatCount, .infinity)
        XCTAssertEqual(spin.preferredFrameRateRange.preferred, 8)

        first.configure(isRunning: false, motionEnabled: true)
        XCTAssertNil(firstLayers[0].animationKeys())
        XCTAssertFalse(firstLayers[1].isHidden)
        let reveal = try XCTUnwrap(firstLayers[1].animation(forKey: "conversation.completed"))
        XCTAssertEqual(reveal.repeatCount, 0)
        XCTAssertLessThan(reveal.duration, 0.5)
        XCTAssertNotNil(secondLayers[0].animation(forKey: "conversation.running"))
        first.configure(isRunning: false, motionEnabled: true)
        first.startLayerAnimation()
        let sameReveal = try XCTUnwrap(firstLayers[1].animation(forKey: "conversation.completed"))
        XCTAssertEqual(sameReveal.beginTime, reveal.beginTime,
                       "Repeated updates must not restart the one-time reveal")
        XCTAssertTrue(sameReveal.isRemovedOnCompletion)
        XCTAssertEqual(firstLayers[1].strokeEnd, 1, "The settled model retains the full check")
        first.removeFromSuperview()
        canvas.addSubview(first)
        XCTAssertNil(firstLayers[1].animation(forKey: "conversation.completed"))

        // Another turn immediately replaces the check with the running arc.
        first.configure(isRunning: true, motionEnabled: true)
        XCTAssertTrue(firstLayers[1].isHidden)
        XCTAssertNotNil(firstLayers[0].animation(forKey: "conversation.running"))
        first.configure(isRunning: true, motionEnabled: false)
        XCTAssertNil(firstLayers[0].animationKeys())
        first.configure(isRunning: true, motionEnabled: true)
        first.isHidden = true
        XCTAssertNil(firstLayers[0].animationKeys())
        first.isHidden = false
        XCTAssertNotNil(firstLayers[0].animation(forKey: "conversation.running"))
        second.removeFromSuperview()
        XCTAssertNil(secondLayers[0].animationKeys())
    }

    @MainActor
    func testSwiftUIStatusUsesTheAppMotionSwitchAndUpdatesWithoutMotion() throws {
        _ = NSApplication.shared
        func content(running: Bool, motion: Bool) -> some View {
            ConversationStatusView(activity: running
                ? .running(startedAt: .now) : .completed(completedAt: .now))
                .environment(\.notchMotionEnabled, motion)
        }
        func status(in view: NSView) -> ConversationStatusLayerView? {
            if let view = view as? ConversationStatusLayerView { return view }
            return view.subviews.lazy.compactMap { status(in: $0) }.first
        }
        let host = NSHostingView(rootView: content(running: true, motion: true))
        host.frame = NSRect(x: 0, y: 0, width: 16, height: 16)
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(status(in: host))
        XCTAssertTrue(view.animationIsRequested)
        host.rootView = content(running: true, motion: false)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(view.animationIsRequested)
        host.rootView = content(running: false, motion: false)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(try shapes(view)[1].isHidden)
    }

    @MainActor
    func testProductionRowsKeepTheirStatusRenderersWhenChatsReorder() throws {
        _ = NSApplication.shared
        let suite = "ConversationStatusTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let sessions = ["first", "second"].map { id in
            SessionActivity(threadID: id, turnID: "turn", title: id, cwd: "/demo",
                            originator: nil, startedAt: now, lastActivityAt: now)
        }
        let running = ConversationSummary(session: sessions[0], activity: .running(startedAt: now))
        let completed = ConversationSummary(session: sessions[1], activity: .completed(completedAt: now))
        func state(_ rows: [ConversationSummary]) -> NotchPresentationState {
            .expanded(ExpandedContent(sessions: [sessions[0]], conversations: rows,
                                      headerConversation: running, usage: nil))
        }
        let size = CGSize(width: 420, height: 360)
        let model = NotchViewModel(state: state([running, completed]), now: now,
                                   surfaceSize: size, animationsEnabled: false)
        let host = NSHostingView(rootView: NotchView(model: model).defaultAppStorage(defaults))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        func statuses(in view: NSView) -> [ConversationStatusLayerView] {
            (view as? ConversationStatusLayerView).map { [$0] }
                ?? view.subviews.flatMap { statuses(in: $0) }
        }
        func orderedStatuses() -> [ConversationStatusLayerView] {
            statuses(in: host).sorted {
                $0.convert($0.bounds, to: host).midY < $1.convert($1.bounds, to: host).midY
            }
        }
        let before = orderedStatuses()
        XCTAssertEqual(before.count, 2)
        let first = try XCTUnwrap(before.first)
        let second = try XCTUnwrap(before.last)
        XCTAssertTrue(try shapes(first)[1].isHidden)
        XCTAssertFalse(try shapes(second)[1].isHidden)
        model.update(state: state([completed, running]), now: now, surfaceSize: size,
                     animationsEnabled: false)
        host.layoutSubtreeIfNeeded()
        let after = orderedStatuses()
        XCTAssertEqual(after.count, 2)
        XCTAssertTrue(after.first === second, "The completed chat must retain its own renderer")
        XCTAssertTrue(after.last === first, "The running chat must retain its own renderer")
    }
}
