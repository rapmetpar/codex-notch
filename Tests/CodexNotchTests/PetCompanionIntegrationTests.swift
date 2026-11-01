import AppKit
import Combine
import ImageIO
import SwiftUI
import XCTest
@testable import CodexNotch

final class PetCompanionIntegrationTests: XCTestCase {
    private func session(at now: Date) -> SessionActivity {
        SessionActivity(threadID: "synthetic", turnID: "turn", title: "Synthetic task", cwd: "/example",
            originator: nil, startedAt: now.addingTimeInterval(-30), lastActivityAt: now)
    }

    /// Generated in-process; no personal artwork or catalog fixture is checked in.
    private func makeLibrary(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let context = try XCTUnwrap(CGContext(data: nil, width: 1536, height: 2288, bitsPerComponent: 8,
            bytesPerRow: 1536 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for row in 0..<11 { for column in 0..<8 {
            let x = CGFloat(column * 192), y = CGFloat(row * 208)
            context.setFillColor(NSColor.systemTeal.cgColor)
            context.fillEllipse(in: CGRect(x: x + 35, y: y + 20, width: 122, height: 140))
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: CGRect(x: x + 59, y: y + 106, width: 24, height: 28))
            context.fillEllipse(in: CGRect(x: x + 108, y: y + 106, width: 24, height: 28))
            context.setFillColor(NSColor.black.cgColor)
            context.fillEllipse(in: CGRect(x: x + 67, y: y + 112, width: 10, height: 12))
            context.fillEllipse(in: CGRect(x: x + 116, y: y + 112, width: 10, height: 12))
        } }
        let image = try XCTUnwrap(context.makeImage())
        for filename in ["one.png", "two.png"] {
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
                directory.appendingPathComponent(filename) as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
        }
        let metadata = try PetAtlasMetadata.standard(spriteVersion: 2)
        let manifest = PetLibraryManifest(schemaVersion: 1, pets: [
            .init(id: "synthetic_one", name: "Synthetic One", atlas: "one.png", spriteVersion: 2, metadata: metadata),
            .init(id: "synthetic_two", name: "Synthetic Two", atlas: "two.png", spriteVersion: 2, metadata: metadata)
        ])
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
    }

    @MainActor
    private func awaitOperation(_ companion: PetCompanionController, action: () -> Void) {
        let done = expectation(description: "Serialized library operation finished")
        let subscription = companion.$isBusy.dropFirst().filter { !$0 }.prefix(1).sink { _ in done.fulfill() }
        action()
        wait(for: [done], timeout: 10)
        withExtendedLifetime(subscription) {}
        XCTAssertFalse(companion.isBusy)
        XCTAssertFalse(companion.hasError)
    }

    @MainActor
    func testEveryImportedChoiceAndOffSurviveControllerRestartWithoutChangingOtherSettings() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let package = temp.appendingPathComponent("package")
        try makeLibrary(at: package)
        let store = PetLibraryStore(rootURL: temp.appendingPathComponent("app-support/PetLibrary"))
        let suite = "PetCompanionIntegration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0, forKey: RecentConversationLimit.storageKey)
        defaults.set("ru", forKey: AppLanguage.storageKey)
        defaults.set("elapsed", forKey: FloatingCenterStyle.storageKey)
        let now = Date(timeIntervalSince1970: 30_000)
        let completion = CompletedSession(session: session(at: now), completedAt: now)
        let readStore = ConversationReadStore(defaults: defaults)
        readStore.acknowledge(completion, threadLinkOpened: true)
        let receiptBytes = defaults.data(forKey: ConversationReadStore.storageKey)
        let companion = PetCompanionController(store: store, defaults: defaults, loadImmediately: false)
        XCTAssertFalse(companion.hasSelectedPet)
        awaitOperation(companion) { companion.importLibrary(from: package) }
        XCTAssertEqual(companion.library.entries.map(\.id), ["synthetic_one", "synthetic_two"])
        XCTAssertNil(companion.library.selectedPetID, "Import never opts in")
        for choice in ["synthetic_one", "synthetic_two"] {
            awaitOperation(companion) { companion.select(choice) }
            XCTAssertTrue(companion.hasSelectedPet)
            XCTAssertEqual(companion.atlas?.clips[.workRunning]?.durations, [0.12, 0.12, 0.12, 0.12, 0.12, 0.22])
            let restarted = PetCompanionController(store: store, defaults: defaults, loadImmediately: false)
            awaitOperation(restarted) { restarted.reload() }
            XCTAssertEqual(restarted.library.selectedPetID, choice)
            XCTAssertTrue(restarted.hasSelectedPet)
        }
        try FileManager.default.removeItem(at: package)
        awaitOperation(companion) { companion.reload() }
        XCTAssertTrue(companion.hasSelectedPet, "Import owns its copied assets, not the source folder")
        awaitOperation(companion) { companion.select(nil) }
        companion.observe(activeSessions: [], completions: [completion], isHovered: false, now: now)
        companion.observe(activeSessions: [], completions: [completion], isHovered: true, now: now.addingTimeInterval(1))
        XCTAssertFalse(companion.hasSelectedPet)
        XCTAssertNil(try store.load().selectedPetID)
        XCTAssertEqual(defaults.integer(forKey: RecentConversationLimit.storageKey), 0)
        XCTAssertEqual(defaults.string(forKey: AppLanguage.storageKey), "ru")
        XCTAssertEqual(defaults.string(forKey: FloatingCenterStyle.storageKey), "elapsed")
        XCTAssertEqual(defaults.data(forKey: ConversationReadStore.storageKey), receiptBytes,
            "Selection, visibility and hover never mutate read receipts")
    }

    @MainActor
    func testExplicitExportedCollectionUsesEveryChoiceThroughNativeScene() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEX_NOTCH_TEST_PET_PACKAGE"] else {
            throw XCTSkip("Set CODEX_NOTCH_TEST_PET_PACKAGE to exercise an explicitly exported collection")
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = PetLibraryStore(rootURL: temp.appendingPathComponent("library"))
        try store.importLibrary(from: URL(fileURLWithPath: path))
        let suite = "PetCompanionCollection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let companion = PetCompanionController(store: store, defaults: defaults, loadImmediately: false)
        awaitOperation(companion) { companion.reload() }
        XCTAssertFalse(companion.library.entries.isEmpty)
        for entry in companion.library.entries {
            awaitOperation(companion) { companion.select(entry.id) }
            XCTAssertEqual(companion.library.selectedPetID, entry.id)
            let atlas = try XCTUnwrap(companion.atlas)
            XCTAssertEqual(atlas.geometry.rows, entry.spriteVersion == 1 ? 9 : 11)
            XCTAssertEqual(atlas.clips.count, 9)
            let stage = PetCompanionStageView(frame: CGRect(x: 0, y: 0, width: 300, height: 104))
            for pose in [PetCompanionPose.idle, .work, .walkLeft, .walkRight,
                         .greeting(token: "fixture-greeting"), .celebration(token: "fixture-completion")] {
                stage.configure(scene: .init(atlas: atlas, name: entry.name, pose: pose, session: PetCompanionSceneSession()),
                    compact: false, animationsEnabled: false, reduceMotion: false)
                stage.layoutSubtreeIfNeeded()
                XCTAssertNotNil(stage.sprite.spriteLayer.contents)
                XCTAssertTrue(stage.bounds.contains(stage.sprite.frame))
            }
            stage.dismantle()
        }
        awaitOperation(companion) { companion.select(nil) }
        XCTAssertFalse(companion.hasSelectedPet)
    }

    @MainActor
    func testHostedIslandUsesOwnStageBelowCameraAndLeavesCompactQuotaLanesAlone() throws {
        _ = NSApplication.shared
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try makeLibrary(at: temp.appendingPathComponent("package"))
        let store = PetLibraryStore(rootURL: temp.appendingPathComponent("library"))
        try store.importLibrary(from: temp.appendingPathComponent("package"))
        try store.selectPet(id: "synthetic_one")
        let suite = "PetCompanionHosted.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("pet", forKey: FloatingCenterStyle.storageKey)
        defaults.set("clockwiseRing", forKey: QuotaDisplayStyle.storageKey)
        let companion = PetCompanionController(store: store, defaults: defaults, loadImmediately: false)
        awaitOperation(companion) { companion.reload() }
        let now = Date(timeIntervalSince1970: 20_000)
        let session = session(at: now)
        let usage = UsageSnapshot(windows: [UsageWindow(id: "weekly", kind: .weekly, usedPercent: 30),
            UsageWindow(id: "five-hour", kind: .rolling(hours: 5), usedPercent: 40)])
        let content = ExpandedContent(sessions: [session], conversations: [], headerConversation: nil, usage: usage)
        let states: [(String, NotchPresentationState)] = [
            ("idle", .quotaCompact(nil)), ("running", .workingCompact(primary: session, count: 1, usage: usage)),
            ("completed", .completedCompact(session, usage: usage)), ("expanded", .expanded(content))
        ]
        for layout in [NotchLayoutMode.notch, .floatingBar] {
            for (label, state) in states {
                for motion in [true, false] {
                    let expanded = label == "expanded"
                    companion.observe(activeSessions: label == "running" || expanded ? [session] : [],
                        completions: label == "completed" ? [.init(session: session, completedAt: now)] : [],
                        isHovered: expanded, now: now)
                    let width: CGFloat = layout == .notch ? 257 : NotchFloatingBarLayout.compactWidth
                    let height: CGFloat = layout == .notch ? 38 : 30
                    let size = expanded ? CGSize(width: 420, height: 420) : CGSize(width: width, height: height)
                    let model = NotchViewModel(state: state, now: now, layoutMode: layout,
                        cameraSafeAreaInset: height, compactWidth: width, compactHeight: height,
                        surfaceSize: size, animationsEnabled: motion)
                    let hosting = NSHostingView(rootView: NotchView(model: model, companion: companion)
                        .defaultAppStorage(defaults).environment(\.displayScale, 2)
                        .frame(width: size.width, height: size.height))
                    hosting.sizingOptions = []
                    hosting.frame = NSRect(origin: .zero, size: size)
                    hosting.layoutSubtreeIfNeeded()
                    try exportRender(hosting, name: "\(layout)-\(label)-motion-\(motion)")
                    let stages = descendants(PetCompanionStageView.self, in: hosting)
                    XCTAssertEqual(stages.count, expanded || layout == .floatingBar ? 1 : 0,
                        "\(layout) \(label) must have exactly the intended safe scene")
                    for stage in stages {
                        let rect = stage.convert(stage.bounds, to: hosting)
                        XCTAssertGreaterThan(rect.width, 0)
                        XCTAssertLessThanOrEqual(rect.maxX, size.width + 0.01)
                        if expanded {
                            XCTAssertGreaterThanOrEqual(rect.minY, height + 8 - 0.01)
                            XCTAssertEqual(rect.height, PetCompanionLayout.stageHeight, accuracy: 0.01)
                        }
                        XCTAssertFalse(stage.layerAnimationIsRunning, "Detached test surface must stay stopped")
                        XCTAssertFalse(stage.sprite.layerAnimationIsRunning)
                    }
                    if label == "running" || expanded {
                        let gradients = descendants(QuotaGradientLayerView.self, in: hosting)
                        XCTAssertEqual(gradients.count, motion ? 4 : 0,
                            "Both five-hour and weekly rings retain their lanes with a companion")
                        let laneOffset: CGFloat = layout == .notch ? width / 2 - 23 : width / 2 - 8 - 15
                        for gradient in gradients {
                            let rect = gradient.convert(gradient.bounds, to: hosting)
                            let expectedX = size.width / 2 + (rect.midX < size.width / 2 ? -laneOffset : laneOffset)
                            XCTAssertEqual(rect.midX, expectedX, accuracy: 0.01,
                                "Empty expanded pet center must still reserve its full lane")
                        }
                    }
                }
            }
        }
        for language in AppLanguage.allCases {
            let hosting = NSHostingView(rootView: PetCompanionSettingsView(companion: companion, language: language)
                .frame(width: 528, height: 520))
            hosting.frame = CGRect(x: 0, y: 0, width: 528, height: 520)
            hosting.layoutSubtreeIfNeeded()
            try exportRender(hosting, name: "settings-\(language.rawValue)")
        }
    }

    @MainActor
    func testStageStopsForEitherMotionSwitchAndDoesNotReplayJumpAfterRemount() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try makeLibrary(at: temp)
        let entry = PetCatalogEntry(id: "synthetic", name: "Synthetic", atlasURL: temp.appendingPathComponent("one.png"),
            spriteVersion: 2, metadata: try .standard(spriteVersion: 2))
        let atlas = try PetCompanionAtlasAdapter.decode(entry)
        let session = PetCompanionSceneSession()
        for app in [true, false] { for reduce in [true, false] {
            let view = PetCompanionStageView(frame: CGRect(x: 0, y: 0, width: 300, height: 104))
            view.configure(scene: .init(atlas: atlas, name: "Synthetic", pose: .walkRight, session: session),
                compact: false, animationsEnabled: app, reduceMotion: reduce)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.animationIsRequested, app && !reduce && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            XCTAssertEqual(view.sprite.animationIsRequested, app && !reduce && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            XCTAssertFalse(view.layerAnimationIsRunning)
            XCTAssertFalse(view.sprite.layerAnimationIsRunning)
            view.dismantle()
            XCTAssertFalse(view.animationIsRequested)
            XCTAssertFalse(view.sprite.animationIsRequested)
        } }
        let context = PetCompanionSceneContext(atlas: atlas, name: "Synthetic", pose: .celebration(token: "fresh-event"), session: session)
        let first = PetCompanionStageView(frame: CGRect(x: 0, y: 0, width: 300, height: 104))
        first.configure(scene: context, compact: false, animationsEnabled: false, reduceMotion: false)
        first.configure(scene: context, compact: false, animationsEnabled: true, reduceMotion: false)
        XCTAssertFalse(first.animationIsRequested, "Disabled one-shot must not queue a jump")
        let remounted = PetCompanionStageView(frame: first.frame)
        remounted.configure(scene: context, compact: false, animationsEnabled: true, reduceMotion: false)
        XCTAssertFalse(remounted.animationIsRequested, "One-shot identity survives scene mounts")
    }

    @MainActor
    func testVisibleFiniteJumpSurvivesUnrelatedUpdatesAndStopsOnDetachment() async throws {
        _ = NSApplication.shared
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try makeLibrary(at: temp)
        let entry = PetCatalogEntry(id: "synthetic", name: "Synthetic", atlasURL: temp.appendingPathComponent("one.png"),
            spriteVersion: 2, metadata: try .standard(spriteVersion: 2))
        let atlas = try PetCompanionAtlasAdapter.decode(entry)
        let scene = PetCompanionSceneContext(atlas: atlas, name: "Synthetic", pose: .celebration(token: "visible-event"),
            session: PetCompanionSceneSession())
        let screen = try XCTUnwrap(NSScreen.main)
        let panel = NotchPanel(contentRect: CGRect(x: screen.visibleFrame.midX - 150,
            y: screen.visibleFrame.midY, width: 300, height: 104))
        let stage = PetCompanionStageView(frame: CGRect(x: 0, y: 0, width: 300, height: 104))
        panel.contentView = stage
        defer { stage.dismantle(); panel.orderOut(nil) }
        stage.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
        for _ in 0..<20 {
            while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            NSApp.updateWindows()
            CATransaction.flush()
            if panel.occlusionState.contains(.visible) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(panel.occlusionState.contains(.visible))
        stage.configure(scene: scene, compact: false, animationsEnabled: true, reduceMotion: false)
        stage.layoutSubtreeIfNeeded()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertFalse(stage.animationIsRequested)
            return
        }
        let animation = try XCTUnwrap(stage.sprite.layer?.animation(forKey: PetCompanionStageView.motionKey))
        XCTAssertEqual(animation.duration, 0.84, accuracy: 0.001)
        XCTAssertEqual(animation.repeatCount, 0)
        stage.configure(scene: scene, compact: false, animationsEnabled: true, reduceMotion: false)
        stage.layoutSubtreeIfNeeded()
        let refreshed = try XCTUnwrap(stage.sprite.layer?.animation(forKey: PetCompanionStageView.motionKey))
        XCTAssertEqual(refreshed.beginTime, animation.beginTime, "A clock/read/UI refresh must neither cancel nor restart the jump")
        panel.contentView = nil
        XCTAssertNil(stage.sprite.layer?.animation(forKey: PetCompanionStageView.motionKey))
        XCTAssertFalse(stage.layerAnimationIsRunning)
        XCTAssertFalse(stage.sprite.layerAnimationIsRunning)
    }

    @MainActor
    private func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(type, in: $0) }
    }

    @MainActor
    private func exportRender(_ view: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["PET_SCENE_RENDER_DIR"] else { return }
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: root.appendingPathComponent(name + ".png"))
    }
}
