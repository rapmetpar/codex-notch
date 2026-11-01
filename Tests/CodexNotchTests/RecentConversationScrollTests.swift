import AppKit
import SwiftUI
import XCTest
@testable import CodexNotch

final class RecentConversationScrollTests: XCTestCase {
    @MainActor
    func testTwentyChatsScrollToTheLastRowInBothLayoutsWithoutGrowingTheCard() throws {
        _ = NSApplication.shared
        for mode in [NotchLayoutMode.notch, .floatingBar] {
            for motionEnabled in [false, true] {
                let (hosting, model, window) = makeHost(count: 20, mode: mode, motionEnabled: motionEnabled)
                defer { window.contentView = nil }
                let scroll = try XCTUnwrap(scrollViews(in: hosting).first)
                let document = try XCTUnwrap(scroll.documentView)
                XCTAssertEqual(scroll.contentSize.height, 200, accuracy: 1)
                XCTAssertGreaterThanOrEqual(document.bounds.height, 20 * 40 - 1)
                XCTAssertLessThanOrEqual(scroll.frame.maxY, hosting.bounds.maxY)
                document.scroll(NSPoint(x: 0, y: document.bounds.maxY))
                scroll.reflectScrolledClipView(scroll.contentView)
                XCTAssertGreaterThan(scroll.documentVisibleRect.minY, 0)
                XCTAssertEqual(scroll.documentVisibleRect.maxY, document.bounds.maxY, accuracy: 1)
                let scrolledOrigin = scroll.documentVisibleRect.origin
                model.updateClock(now: model.now.addingTimeInterval(1))
                hosting.layoutSubtreeIfNeeded()
                XCTAssertEqual(scroll.documentVisibleRect.origin, scrolledOrigin,
                               "Clock ticks must not reset history to the first five chats")
            }
        }
    }

    @MainActor
    func testZeroThroughTwentyChatsUseBoundedGroupedViewportAndZeroHidesHeadings() {
        _ = NSApplication.shared
        for count in 0...20 {
            let (hosting, _, window) = makeHost(count: count, mode: .notch, motionEnabled: false)
            defer { window.contentView = nil }
            // PROJECT-GROUPS-001 supersedes five chat rows: headings consume pixels,
            // never display slots. Four rows plus one header fit; five must scroll.
            XCTAssertEqual(scrollViews(in: hosting).isEmpty, count <= 4)
        }
    }

    @MainActor
    private func makeHost(count: Int, mode: NotchLayoutMode, motionEnabled: Bool)
        -> (NSHostingView<NotchView>, NotchViewModel, NSWindow) {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let conversations = (0..<count).map { index in
            let session = SessionActivity(
                threadID: "scroll-\(index)", turnID: "turn", title: "Chat \(index + 1)",
                cwd: "/demo", originator: nil, startedAt: now, lastActivityAt: now
            )
            return ConversationSummary(session: session, activity: .completed(completedAt: now))
        }
        let content = ExpandedContent(sessions: [], conversations: conversations,
                                      headerConversation: conversations.first, usage: nil)
        let size = NSSize(width: 420, height: 32 + (count == 0
            ? NotchExpandedLayout.quotaContentHeight
            : NotchExpandedLayout.taskContentHeight(conversationCount: count, projectCount: count == 0 ? 0 : 1)))
        let model = NotchViewModel(state: .expanded(content), now: now, layoutMode: mode,
                                  cameraSafeAreaInset: mode == .notch ? 32 : 0,
                                  compactWidth: 257, compactHeight: 32,
                                  surfaceSize: size, animationsEnabled: motionEnabled)
        let hosting = NSHostingView(rootView: NotchView(model: model))
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        return (hosting, model, window)
    }

    @MainActor
    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
}
