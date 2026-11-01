import AppKit
import SwiftUI
import XCTest
@testable import CodexNotch

final class ProjectIslandIntegrationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func content(count: Int) -> ExpandedContent {
        let rows = (0..<count).map { index -> ConversationSummary in
            let session = SessionActivity(threadID: "synthetic-\(index)", turnID: "turn",
                title: "Synthetic chat \(index + 1)", cwd: "/synthetic/Project \(index / 3 + 1)", originator: nil,
                startedAt: now, lastActivityAt: now)
            return ConversationSummary(session: session,
                activity: index == 0 ? .running(startedAt: now) : .completed(completedAt: now), isViewed: index % 3 == 2)
        }
        return ExpandedContent(sessions: [], conversations: rows, headerConversation: rows.first, usage: UsageSnapshot(windows: [UsageWindow(id: "weekly", kind: .weekly,
                                   usedPercent: 36, resetAt: now.addingTimeInterval(86_400))], fetchedAt: now),
                               allProjectIDs: rows.reduce(into: []) { if !$0.contains($1.project.id) { $0.append($1.project.id) } })
    }

    @MainActor
    private func settle(_ host: NSView) {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    @MainActor
    private func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
    }

    @MainActor
    private func pixels(_ host: NSView, rect: CGRect) throws -> Data {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let image = try XCTUnwrap(bitmap.cgImage?.cropping(to: CGRect(x: rect.minX * scale,
            y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try XCTUnwrap(context.data), count: image.width * image.height * 4)
    }

    @MainActor
    private func scrollViews(_ view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews($0) }
    }

    @MainActor
    func testGroupedSceneScrollKeepsFooterAndQuotaOutsideAndPreservesSizeAfterReorder() throws {
        _ = NSApplication.shared
        let suite = "ProjectIslandIntegration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("en", forKey: AppLanguage.storageKey)
        let value = content(count: 20)
        for mode in [NotchLayoutMode.notch, .floatingBar] {
            for motion in [false, true] {
                let size = NSSize(width: 420, height: 32 + NotchExpandedLayout.taskContentHeight(
                    conversationCount: 20, projectCount: value.projectSections.count))
                let model = NotchViewModel(state: .expanded(value), now: now, layoutMode: mode,
                    cameraSafeAreaInset: mode == .notch ? 32 : 0, compactWidth: 257, compactHeight: 32,
                    surfaceSize: size, animationsEnabled: motion)
                let host = NSHostingView(rootView: ProjectIslandScenePreview(model: model).defaultAppStorage(defaults))
                host.sizingOptions = []
                // Production panel stays nonactivating and cannot take key focus.
                let window = NotchPanel(contentRect: NSRect(origin: .zero, size: size))
                window.isReleasedWhenClosed = false
                window.contentView = host
                host.frame = NSRect(origin: .zero, size: size)
                window.orderFrontRegardless()
                defer { window.orderOut(nil); window.contentView = nil }
                settle(host)
                let scroll = try XCTUnwrap(scrollViews(host).first)
                let document = try XCTUnwrap(scroll.documentView)
                XCTAssertEqual(scroll.contentSize.height, 200, accuracy: 1)
                XCTAssertGreaterThanOrEqual(document.bounds.height, 20 * 40 + CGFloat(value.projectSections.count) * 32 - 1)
                let scrollFrame = scroll.convert(scroll.bounds, to: host)
                XCTAssertGreaterThanOrEqual(scrollFrame.minY, 30)
                XCTAssertLessThanOrEqual(scrollFrame.maxY, host.bounds.maxY - 30)
                // CGImage coordinates start at the top, independent of NSView flipping.
                let quotaRect = CGRect(x: 14, y: 40, width: 392, height: 80)
                let footerRect = CGRect(x: 14, y: host.bounds.height - 42, width: 392, height: 32)
                let quotaPixels = try pixels(host, rect: quotaRect)
                let footerPixels = try pixels(host, rect: footerRect)
                document.scroll(NSPoint(x: 0, y: document.bounds.maxY))
                scroll.reflectScrolledClipView(scroll.contentView)
                settle(host)
                XCTAssertEqual(scroll.documentVisibleRect.maxY, document.bounds.maxY, accuracy: 1)
                XCTAssertEqual(scroll.convert(scroll.bounds, to: host), scrollFrame,
                               "Scrolling cannot change the quota/footer reserved areas")
                XCTAssertEqual(try pixels(host, rect: quotaRect), quotaPixels, "Weekly quota/reset stay stationary")
                XCTAssertEqual(try pixels(host, rect: footerRect), footerPixels, "Footer stays stationary")
                let originalSize = model.surfaceSize
                var reordered = value
                let ids = value.allProjectIDs
                let order = ConversationProjectOrder(ids: [ids.last!] + Array(ids.dropLast()))
                reordered = ExpandedContent(sessions: value.sessions,
                    conversations: order.sorted(value.conversations, categories: .defaultOrder),
                    headerConversation: value.headerConversation, usage: value.usage,
                    allProjectIDs: order.availableIDs(in: value.conversations))
                _ = model.update(state: .expanded(reordered), now: now, layoutMode: mode,
                    cameraSafeAreaInset: mode == .notch ? 32 : 0, compactWidth: 257, compactHeight: 32,
                    surfaceSize: size, animationsEnabled: motion)
                settle(host)
                XCTAssertEqual(model.surfaceSize, originalSize)
                XCTAssertEqual(scrollViews(host).first?.contentSize.height ?? 0, 200, accuracy: 1)
                if let folder = ProcessInfo.processInfo.environment["NOTCH_PROJECT_PREVIEW_DIR"], !motion {
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                        URL(fileURLWithPath: folder).appendingPathComponent("projects-\(mode == .notch ? "notch" : "floating").png"))
                }
            }
        }
    }

    @MainActor
    func testNativeAccessibilityButtonActuallyReordersOnNonKeyPanelAndLocalizedPreviewFits() throws {
        _ = NSApplication.shared
        let initial = content(count: 6)
        for language in AppLanguage.allCases {
            let model = NotchViewModel(state: .expanded(initial), now: now)
            var changed: [String] = []
            model.onProjectOrderChange = { changed = $0 }
            let host = NSHostingView(rootView: ProjectConversationListView(content: initial, now: now, language: language,
                onOpenThread: { _ in }, onDropProjects: model.dropProjects, onMoveProject: model.moveProject)
                .frame(width: 392).background(Color.black))
            let size = NSSize(width: 392, height: 200)
            host.sizingOptions = []
            let panel = NotchPanel(contentRect: NSRect(origin: .zero, size: size))
            panel.isReleasedWhenClosed = false
            panel.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            panel.orderFrontRegardless()
            defer { panel.orderOut(nil); panel.contentView = nil }
            settle(host)
            let ax = buttons(host)
            let firstTitle = initial.projectSections[0].title(language: language)
            let button = try XCTUnwrap(ax.first { element in
                let label = element.accessibilityLabel() ?? ""
                return label.contains(firstTitle) && element.isEnabled
            })
            let disabled = try XCTUnwrap(ax.first { ($0.accessibilityLabel() ?? "").contains(firstTitle) && !$0.isEnabled })
            XCTAssertFalse(disabled.accessibilityPerformPress(), "The first project cannot move above itself")
            XCTAssertTrue(button.accessibilityPerformPress())
            settle(host)
            XCTAssertEqual(changed, Array(initial.allProjectIDs.reversed()), "Actual accessible heading button must reach production model")
            XCTAssertFalse(panel.canBecomeKey, "Project controls must not steal focus from the active chat")
            if let folder = ProcessInfo.processInfo.environment["NOTCH_PROJECT_PREVIEW_DIR"] {
                let renderer = ImageRenderer(content: ProjectHeadingDragPreview(title: firstTitle))
                renderer.scale = 2
                let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                    URL(fileURLWithPath: folder).appendingPathComponent("project-drag-\(language.rawValue).png"))
            }
        }
    }

    func testGroupedHeightNeverExceedsPriorMaximumAndSmallCardsIncludeExactHeaders() {
        for count in 1...20 {
            for projects in 1...count {
                let height = NotchExpandedLayout.conversationListHeight(conversationCount: count, projectCount: projects)
                XCTAssertLessThanOrEqual(height, 200)
                XCTAssertEqual(height, min(200, CGFloat(count * 40 + projects * 32)))
                XCTAssertLessThanOrEqual(NotchExpandedLayout.taskContentHeight(conversationCount: count, projectCount: projects),
                    NotchExpandedLayout.taskContentHeight(conversationCount: 20))
            }
        }
        XCTAssertEqual(NotchExpandedLayout.taskContentHeight(conversationCount: 2, projectCount: 2)
            - NotchExpandedLayout.taskContentHeight(conversationCount: 2), 64)
    }
}
