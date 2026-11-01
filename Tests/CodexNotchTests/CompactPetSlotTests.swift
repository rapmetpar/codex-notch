import AppKit
import QuartzCore
import XCTest
@testable import CodexNotch

final class CompactPetSlotTests: XCTestCase {
    private func scene() throws -> PetCompanionSceneContext {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 88, bitsPerComponent: 8,
            bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemTeal.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 88))
        let atlas = try PetSpriteAtlas(image: XCTUnwrap(context.makeImage()),
            geometry: PetSpriteGeometry(columns: 8, rows: 11, cellWidth: 8, cellHeight: 8),
            clips: PetSpriteAtlas.standardClips())
        return PetCompanionSceneContext(atlas: atlas, name: "Synthetic", pose: .work, session: PetCompanionSceneSession())
    }
    private let fiveHour = UsageWindow(id: "five-hour", kind: .rolling(hours: 5), usedPercent: 37)

    func testCadenceHasReadableHoldsSmoothFadesAndOnlyRealIndicators() {
        for hasQuota in [false, true] { for activity in [QuotaRingActivity.idle, .running, .completed] {
            let cycle = CompactPetSlotCycle(hasFiveHour: hasQuota, activity: activity)
            XCTAssertEqual(cycle.contents.contains(.fiveHour), hasQuota)
            XCTAssertEqual(cycle.contents.contains(.completed), activity == .completed)
            XCTAssertEqual(cycle.contents.first, .pet)
            for (index, content) in cycle.contents.enumerated() {
                let start = Double(index) * (CompactPetSlotCycle.hold + CompactPetSlotCycle.fade)
                for offset in [0.0, 1, 4.4] {
                    let hold = cycle.sample(elapsed: start + offset)
                    XCTAssertEqual(hold.current, content)
                    XCTAssertNil(hold.next)
                    XCTAssertEqual(hold.fadeProgress, 0)
                }
                if cycle.contents.count > 1 {
                    let fade = cycle.sample(elapsed: start + CompactPetSlotCycle.hold + CompactPetSlotCycle.fade / 2)
                    XCTAssertEqual(fade.current, content)
                    XCTAssertEqual(fade.next, cycle.contents[(index + 1) % cycle.contents.count])
                    XCTAssertEqual(fade.fadeProgress, 0.5, accuracy: 0.0001)
                }
            }
            XCTAssertEqual(cycle.staticContent, hasQuota ? .fiveHour : (activity == .completed ? .completed : .pet))
        } }
    }

    func testAccessibleStateIsExplicitEvenWhenStaticQuotaOrTaskTitleOccupiesTheSlot() {
        XCTAssertEqual(CompactPetSlotSemantics.state(.running, language: .english), "Running")
        XCTAssertEqual(CompactPetSlotSemantics.state(.completed, language: .english), "Completed")
        XCTAssertEqual(CompactPetSlotSemantics.state(.idle, language: .russian), "Готов")
    }

    @MainActor
    func testCompletionGlyphDescendsToContactThenRisesInNativeCoordinates() throws {
        let view = CompactPetCompletionView(frame: CGRect(x: 0, y: 0, width: 26, height: 28))
        view.layoutSubtreeIfNeeded()
        let shape = try XCTUnwrap(view.layer?.sublayers?.first as? CAShapeLayer)
        var points: [CGPoint] = []
        shape.path?.applyWithBlock { element in
            if element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint {
                points.append(element.pointee.points[0])
            }
        }
        XCTAssertEqual(points.count, 3)
        XCTAssertFalse(view.isFlipped)
        XCTAssertLessThan(points[1].y, points[0].y, "A check descends before its long rising stroke, not an inverted caret")
        XCTAssertGreaterThan(points[2].y, points[0].y)
        XCTAssertGreaterThan(points[2].x, points[1].x)
    }

    @MainActor
    func testStaticGatesKeepOneRectAndNoSpinnerFalseCheckOrFakeQuota() throws {
        _ = NSApplication.shared
        let scene = try scene()
        for height: CGFloat in [24, 28, 38] { for hasQuota in [false, true] {
            for activity in [QuotaRingActivity.idle, .running, .completed] {
                for (app, reduce) in [(false, false), (true, true)] {
                    let view = CompactPetSlotView(frame: CGRect(x: 0, y: 0, width: 26, height: min(28, height)))
                    view.configure(scene: scene, activity: activity, fiveHour: hasQuota ? fiveHour : nil,
                        quotaStyle: .clockwiseRing, appearance: QuotaAppearance(),
                        animationsEnabled: app, reduceMotion: reduce)
                    view.layoutSubtreeIfNeeded()
                    XCTAssertEqual(view.pet.frame, view.quota.frame)
                    XCTAssertEqual(view.pet.frame, view.completion.frame)
                    XCTAssertTrue(view.bounds.contains(view.pet.sprite.frame))
                    XCTAssertEqual(view.visibleContents, [hasQuota ? .fiveHour : (activity == .completed ? .completed : .pet)])
                    XCTAssertEqual(view.completion.isHidden, hasQuota || activity != .completed)
                    XCTAssertFalse(view.pet.sprite.animationIsRequested)
                    XCTAssertFalse(view.animationIsRequested)
                    XCTAssertNil(view.boundaryTimer)
                    XCTAssertNil(view.startedAt)
                    XCTAssertNil(view.hitTest(.zero), "The compact button must retain click/hover ownership")
                    XCTAssertFalse(view.subviews.contains { $0 is ConversationStatusLayerView }, "No loading cue exists")
                    view.dismantle()
                }
            }
        } }
    }

    @MainActor
    func testVisibleCadenceSurvivesRerenderAndValueUpdatesThenPausesOnHideOcclusionAndDetach() async throws {
        _ = NSApplication.shared
        let view = CompactPetSlotView(frame: CGRect(x: 0, y: 0, width: 26, height: 28))
        let scene = try scene()
        let window = NSWindow(contentRect: CGRect(x: (NSScreen.main?.visibleFrame.midX ?? 200) - 13,
                y: (NSScreen.main?.visibleFrame.midY ?? 200) - 14, width: 26, height: 28),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .popUpMenu
        window.contentView = view
        defer { view.dismantle(); window.orderOut(nil); window.contentView = nil }
        func configure(_ quota: UsageWindow?, motion: Bool = true) {
            view.configure(scene: scene, activity: .running, fiveHour: quota,
                quotaStyle: .clockwiseRing, appearance: QuotaAppearance(), animationsEnabled: motion, reduceMotion: false)
            view.layoutSubtreeIfNeeded()
        }
        configure(fiveHour)
        window.orderFrontRegardless()
        for _ in 0..<20 {
            while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            NSApp.updateWindows(); CATransaction.flush()
            if window.occlusionState.contains(.visible) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        if session?["CGSSessionScreenIsLocked"] as? Bool == true {
            throw XCTSkip("Locked desktop session: native cadence needs unlocked WindowServer")
        }
        XCTAssertTrue(window.occlusionState.contains(.visible), "Native window \(window.frame), desktop \(NSScreen.main?.visibleFrame ?? .zero), visible \(window.isVisible), occlusion \(window.occlusionState.rawValue)")
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            XCTAssertNil(view.boundaryTimer)
            return
        }
        configure(fiveHour)
        let started = try XCTUnwrap(view.startedAt)
        let timer = try XCTUnwrap(view.boundaryTimer)
        let sprite = try XCTUnwrap(view.pet.sprite.spriteLayer.animation(forKey: PetSpriteLayerView.animationKey))
        for percent in [37.0, 38, 39] {
            configure(UsageWindow(id: "five-hour", kind: .rolling(hours: 5), usedPercent: percent))
            XCTAssertEqual(view.startedAt, started)
            XCTAssertTrue(view.boundaryTimer === timer, "Value/clock rerenders must not restart hold")
            XCTAssertEqual(view.pet.sprite.spriteLayer.animation(forKey: PetSpriteLayerView.animationKey)?.beginTime, sprite.beginTime)
        }
        // Observe the real native transition after its multi-second readable hold.
        try await Task.sleep(for: .milliseconds(4590))
        XCTAssertEqual(view.visibleContents, [.pet, .fiveHour])
        XCTAssertNotNil(view.pet.layer?.animation(forKey: CompactPetSlotView.fadeKey))
        XCTAssertNotNil(view.quota.layer?.animation(forKey: CompactPetSlotView.fadeKey))
        try await Task.sleep(for: .milliseconds(360))
        XCTAssertEqual(view.visibleContents, [.fiveHour])
        XCTAssertTrue(view.pet.isHidden)
        XCTAssertFalse(view.pet.sprite.layerAnimationIsRunning, "Invisible pet must not animate behind quota")
        XCTAssertNotNil(view.boundaryTimer)
        view.isHidden = true
        XCTAssertNil(view.boundaryTimer)
        XCTAssertNil(view.startedAt)
        let paused = view.elapsed
        view.isHidden = false
        XCTAssertEqual(view.elapsed, paused, accuracy: 0.0001)
        XCTAssertNotNil(view.startedAt)
        window.orderOut(nil)
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        XCTAssertNil(view.boundaryTimer)
        XCTAssertFalse(view.pet.sprite.layerAnimationIsRunning)
        window.contentView = nil
        XCTAssertNil(view.boundaryTimer)
        XCTAssertNil(view.startedAt)
        configure(fiveHour, motion: false)
        XCTAssertEqual(view.visibleContents, [.fiveHour])
        XCTAssertNil(view.boundaryTimer)
    }
}
