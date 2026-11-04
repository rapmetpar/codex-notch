import AppKit
import SwiftUI
import XCTest
@testable import CodexNotch

final class ExpandedLayoutSpacingTests: XCTestCase {
    @MainActor
    func testNativeExpandedSpacingAndContentBounds() throws {
        _ = NSApplication.shared
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let suite = "ExpandedSpacing.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for language in AppLanguage.allCases {
            defaults.set(language.rawValue, forKey: AppLanguage.storageKey)
            for mode in [NotchLayoutMode.notch, .floatingBar] {
                for count in [0, 1, 5, 20] {
                    for kind in [0, 1, 2, 3, 4] {
                        let credits = kind >= 3 ? (0..<3).map { ResetCredit(id: "credit-\($0)", expiresAt: now.addingTimeInterval(86400)) } : []
                        let windows: [UsageWindow] = kind == 0 ? [] : [UsageWindow(id: "weekly", kind: .weekly, usedPercent: 9, resetAt: now.addingTimeInterval(86400))] + (kind == 2 ? [UsageWindow(id: "five", kind: .rolling(hours: 5), usedPercent: 40, resetAt: now.addingTimeInterval(3600))] : [])
                        let usage: UsageSnapshot? = kind == 0 ? nil : UsageSnapshot(windows: windows, resetCreditsAvailable: credits.isEmpty ? nil : credits.count, resetCredits: credits, fetchedAt: now)
                        let rows = (0..<count).map { i -> ConversationSummary in
                            let session = SessionActivity(threadID: "synthetic-\(i)", turnID: "turn", title: "Synthetic chat \(i)", cwd: "/synthetic/Project \(i / 3)", originator: nil, startedAt: now, lastActivityAt: now)
                            return ConversationSummary(session: session, activity: i == 0 ? .running(startedAt: now) : .completed(completedAt: now), isViewed: false)
                        }
                        let active = SessionActivity(threadID: "active", turnID: "turn", title: "Active synthetic task", cwd: "/synthetic/Project 0", originator: nil, startedAt: now, lastActivityAt: now)
                        let content = ExpandedContent(sessions: kind == 2 ? [active] : [], conversations: rows, headerConversation: rows.first, usage: usage)
                        let expanded = kind == 4
                        let height = count == 0 ? NotchExpandedLayout.quotaContentSize(isResetScheduleExpanded: expanded, resetCreditCount: credits.count, hasFiveHourWindow: kind == 2).height : NotchExpandedLayout.taskContentHeight(conversationCount: count, projectCount: content.projectSections.count, isResetScheduleExpanded: expanded, resetCreditCount: credits.count, hasFiveHourWindow: kind == 2)
                        let size = CGSize(width: 420, height: height + 32)
                        let state = NotchPresentationState.expanded(content)
                        let model = NotchViewModel(state: state, now: now, layoutMode: mode, cameraSafeAreaInset: mode == .notch ? 32 : 0, compactWidth: 257, compactHeight: 32, surfaceSize: size, animationsEnabled: false)
                        _ = model.update(state: state, now: now, layoutMode: mode, cameraSafeAreaInset: mode == .notch ? 32 : 0, compactWidth: 257, compactHeight: 32, surfaceSize: size, isResetScheduleExpanded: expanded, animationsEnabled: false)
                        let host = NSHostingView(rootView: NotchView(model: model).defaultAppStorage(defaults).frame(width: size.width, height: size.height))
                        host.sizingOptions = []
                        host.frame = CGRect(origin: .zero, size: size)
                        host.layoutSubtreeIfNeeded()
                        if language.rawValue == "ru", mode == .notch, count == 5, kind == 3,
                           let folder = ProcessInfo.processInfo.environment["NOTCH_SPACING_PREVIEW_DIR"] {
                            let panel = NotchPanel(contentRect: CGRect(origin: .zero, size: size))
                            panel.isReleasedWhenClosed = false
                            panel.contentView = host
                            panel.orderFrontRegardless()
                            host.layoutSubtreeIfNeeded()
                            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                            host.cacheDisplay(in: host.bounds, to: bitmap)
                            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: folder).appendingPathComponent("spacing.png"))
                            panel.orderOut(nil)
                            panel.contentView = nil
                        }
                        func find(_ view: NSView, _ name: String) -> NSView? {
                            if view.identifier?.rawValue == "expanded-layout-" + name { return view }
                            return view.subviews.lazy.compactMap { find($0, name) }.first
                        }
                        func rect(_ name: String) throws -> CGRect {
                            let v = try XCTUnwrap(find(host, name))
                            let r = v.convert(v.bounds, to: host)
                            return host.isFlipped ? r : CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height)
                        }
                        let quota = try rect("quota"), footer = try rect("footer")
                        let context = "\(language.rawValue) mode=\(mode) count=\(count) kind=\(kind)"
                        XCTAssertGreaterThanOrEqual(quota.minY, 39, context)
                        XCTAssertLessThanOrEqual(footer.maxY, size.height - 9, context)
                        XCTAssertGreaterThanOrEqual(footer.maxY, size.height - 15, context)
                        if count > 0 {
                            let recent = try rect("recent"), list = try rect("list")
                            XCTAssertEqual(recent.minY - quota.maxY, 16, accuracy: 1, context)
                            XCTAssertEqual(list.minY - recent.maxY, 8, accuracy: 1, context)
                            XCTAssertEqual(footer.minY - list.maxY, 6, accuracy: 1, context)
                            XCTAssertEqual(list.height, NotchExpandedLayout.conversationListHeight(conversationCount: count, projectCount: content.projectSections.count), accuracy: 1, context)
                        } else {
                            XCTAssertEqual(footer.minY - quota.maxY, 6, accuracy: 1, context)
                        }
                    }
                }
            }
        }
    }
}
