import AppKit
import QuartzCore
import SwiftUI
import XCTest
@testable import CodexNotch

final class PetSpriteTests: XCTestCase {
    private func fixture(rows: Int = 11) throws -> PetSpriteAtlas {
        let width = 8 * 4, height = rows * 6
        let lengths = [6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8]
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let row = y / 6, col = x / 4, i = (y * width + x) * 4
                guard col < lengths[row], !(row == 3 && col == 2) else { continue }
                bytes[i] = UInt8(20 + row * 20)
                bytes[i + 1] = UInt8(20 + col * 25)
                bytes[i + 2] = UInt8((y % 6) * 40)
                bytes[i + 3] = 255
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return try PetSpriteAtlas(image: image,
            geometry: PetSpriteGeometry(columns: 8, rows: rows, cellWidth: 4, cellHeight: 6),
            clips: PetSpriteAtlas.standardClips())
    }

    func testAllPublishedClipsRetainEveryFrameAndExactHolds() throws {
        let states: [PetSpriteState] = [.idle, .runRight, .runLeft, .wave, .jump, .failed, .waiting, .workRunning, .review]
        let milliseconds = [[280,110,110,140,140,320], [120,120,120,120,120,120,120,220],
                            [120,120,120,120,120,120,120,220], [140,140,140,280], [140,140,140,140,280],
                            [140,140,140,140,140,140,140,240], [150,150,150,150,150,260],
                            [120,120,120,120,120,220], [150,150,150,150,150,280]]
        for rows in [9, 11] {
            let atlas = try fixture(rows: rows)
            XCTAssertEqual(atlas.clips.count, 9)
            for (row, state) in states.enumerated() {
                let clip = try XCTUnwrap(atlas.clips[state])
                XCTAssertEqual(clip.row, row)
                XCTAssertEqual(clip.durations, milliseconds[row].map { Double($0) / 1000 })
                let images = try XCTUnwrap(atlas.images(for: state))
                XCTAssertEqual(images.count, milliseconds[row].count)
                XCTAssertEqual(clip.keyTimes.count, images.count + 1)
                XCTAssertEqual(clip.keyTimes.last, 1)
                var time = 0.0
                for (index, hold) in clip.durations.enumerated() {
                    XCTAssertEqual(clip.frameIndex(at: time + hold / 2, looping: true), index)
                    XCTAssertEqual(clip.keyTimes[index], time / clip.duration, accuracy: 0.000001)
                    time += hold
                }
                XCTAssertEqual(clip.frameIndex(at: time + 0.001, looping: false), images.count - 1)
                XCTAssertEqual(clip.frameIndex(at: time + 0.001, looping: true), 0)
            }
        }
    }

    func testWholeCellCroppingPreservesTopRowOrientationAndTransparentFrames() throws {
        let atlas = try fixture()
        for (row, state) in [PetSpriteState.idle, .runRight, .runLeft, .wave, .jump, .failed, .waiting, .workRunning, .review].enumerated() {
            let frames = try XCTUnwrap(atlas.images(for: state))
            for (column, frame) in frames.enumerated() {
                XCTAssertEqual(frame.width, 4)
                XCTAssertEqual(frame.height, 6)
                let rep = NSBitmapImageRep(cgImage: frame)
                let top = try XCTUnwrap(rep.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
                let bottom = try XCTUnwrap(rep.colorAt(x: 3, y: 5)?.usingColorSpace(.deviceRGB))
                if row == 3 && column == 2 {
                    XCTAssertEqual(top.alphaComponent, 0)
                    XCTAssertEqual(bottom.alphaComponent, 0)
                } else {
                    XCTAssertEqual(top.redComponent, CGFloat(20 + row * 20) / 255, accuracy: 0.01)
                    XCTAssertEqual(top.greenComponent, CGFloat(20 + column * 25) / 255, accuracy: 0.01)
                    XCTAssertEqual(top.blueComponent, 0, accuracy: 0.01)
                    XCTAssertEqual(bottom.blueComponent, 200.0 / 255, accuracy: 0.01)
                    XCTAssertEqual(bottom.alphaComponent, 1)
                }
            }
        }
        // Padding columns never appear, and optional look poses are not mistaken for a clip.
        XCTAssertEqual(atlas.images(for: .idle)?.count, 6)
        XCTAssertEqual(atlas.images(for: .wave)?.count, 4)
    }

    func testMalformedMetadataAndImageDimensionsFailClosed() throws {
        XCTAssertThrowsError(try PetSpriteGeometry(columns: .max, rows: 9, cellWidth: 4, cellHeight: 6))
        XCTAssertThrowsError(try PetSpriteClip(state: .idle, row: 0, columns: [0], durations: [.nan]))
        XCTAssertThrowsError(try PetSpriteClip(state: .idle, row: 0, columns: [0], durations: [0]))
        XCTAssertThrowsError(try PetSpriteClip(state: .idle, row: 0, columns: [0, 1], durations: [0.1]))
        XCTAssertThrowsError(try PetSpriteClip(state: .idle, row: 0, columns: [0], durations: [0.1], staticFrameIndex: 1))
        let atlas = try fixture()
        let cell = try XCTUnwrap(atlas.images(for: .idle)?.first)
        let geometry = try PetSpriteGeometry(columns: 1, rows: 1, cellWidth: 4, cellHeight: 6)
        let clip = try PetSpriteClip(state: .idle, row: 0, columns: [0], durations: [0.1])
        XCTAssertThrowsError(try PetSpriteAtlas(image: cell,
            geometry: PetSpriteGeometry(columns: 2, rows: 1, cellWidth: 4, cellHeight: 6), clips: [clip]))
        XCTAssertThrowsError(try PetSpriteAtlas(image: cell, geometry: geometry, clips: [clip, clip]))
        XCTAssertThrowsError(try PetSpriteAtlas(image: cell, geometry: geometry, clips: PetSpriteAtlas.standardClips()))
        XCTAssertThrowsError(try PetSpriteAtlas(url: URL(string: "https://example.com/atlas.png")!, geometry: geometry, clips: [clip]))
    }

    func testOneShotDoesNotReplayOnConfigureReorderRemountOrOldEvent() throws {
        let session = PetSpritePlaybackSession()
        session.configure(state: .wave, playback: .once(token: "turn-A"), now: 10)
        session.resume(at: 10)
        XCTAssertEqual(session.elapsed(at: 10.2, duration: 1), 0.2, accuracy: 0.00001)
        session.configure(state: .wave, playback: .once(token: "turn-A"), now: 10.2)
        XCTAssertEqual(session.elapsed(at: 10.3, duration: 1), 0.3, accuracy: 0.00001)
        session.pause(at: 10.3)
        XCTAssertEqual(session.elapsed(at: 99, duration: 1), 0.3, accuracy: 0.00001)
        session.resume(at: 99)
        XCTAssertEqual(session.elapsed(at: 99.2, duration: 1), 0.5, accuracy: 0.00001)
        XCTAssertEqual(session.elapsed(at: 100, duration: 1), 1)
        session.configure(state: .idle, playback: .loop, now: 101)
        session.configure(state: .wave, playback: .once(token: "turn-A"), now: 102)
        XCTAssertEqual(session.elapsed(at: 102, duration: 1), 1)
        session.configure(state: .jump, playback: .once(token: "turn-B"), now: 103)
        XCTAssertEqual(session.elapsed(at: 103, duration: 1), 0)
        session.finishOneShot()
        XCTAssertEqual(session.elapsed(at: 103, duration: 1), 1)
    }

    func testEventMemoryIsBoundedWithoutReplayingEvictedHistory() {
        let session = PetSpritePlaybackSession()
        for index in 0..<PetSpritePlaybackSession.maximumRememberedEvents {
            session.configure(state: .wave, playback: .once(token: "\(index)"), now: 0)
            XCTAssertEqual(session.elapsed(at: 0, duration: 1), 0)
        }
        session.configure(state: .wave, playback: .once(token: "overflow"), now: 0)
        XCTAssertEqual(session.elapsed(at: 0, duration: 1), 1)
        session.configure(state: .wave, playback: .once(token: "0"), now: 0)
        XCTAssertEqual(session.elapsed(at: 0, duration: 1), 1)
    }

    @MainActor
    func testNativeLayersKeepExactTimingsAndStopWhenDetachedOrMotionOff() async throws {
        _ = NSApplication.shared
        let atlas = try fixture()
        let session = PetSpritePlaybackSession()
        let view = PetSpriteLayerView(frame: CGRect(x: 0, y: 0, width: 40, height: 60))
        let panel = NotchPanel(contentRect: view.frame)
        panel.contentView = view
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.contentView = nil }
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
        func configure(visible: Bool = true, enabled: Bool = true, reduced: Bool = false) {
            view.configure(atlas: atlas, state: .wave, playback: .once(token: "event"), session: session,
                           isVisible: visible, animationsEnabled: enabled, reduceMotion: reduced)
            view.layout()
        }
        configure()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertNil(view.spriteLayer.animationKeys())
            return // Pure/static guards below remain covered independently on any system setting.
        }
        let animation = try XCTUnwrap(view.spriteLayer.animation(forKey: PetSpriteLayerView.animationKey) as? CAKeyframeAnimation)
        XCTAssertEqual(animation.calculationMode, .discrete)
        XCTAssertEqual(animation.duration, 0.7, accuracy: 0.0001)
        XCTAssertEqual(animation.values?.count, 5)
        XCTAssertEqual(animation.keyTimes?.map(\.doubleValue), atlas.clips[.wave]?.keyTimes)
        XCTAssertEqual(animation.repeatCount, 0)
        XCTAssertEqual(animation.preferredFrameRateRange.maximum, 30)
        for index in 0..<500 {
            configure()
            view.setFrameOrigin(CGPoint(x: index % 3, y: index % 2))
        }
        XCTAssertEqual(view.spriteLayer.animationKeys()?.count, 1)
        XCTAssertEqual(view.spriteLayer.animation(forKey: PetSpriteLayerView.animationKey)?.beginTime, animation.beginTime)
        XCTAssertEqual(view.spriteLayer.contentsScale, panel.backingScaleFactor)
        XCTAssertEqual(view.spriteLayer.contentsGravity, .resizeAspect)
        XCTAssertEqual(view.spriteLayer.magnificationFilter, .nearest)
        configure(visible: false)
        XCTAssertNil(view.spriteLayer.animationKeys())
        configure()
        view.isHidden = true
        XCTAssertNil(view.spriteLayer.animationKeys())
        view.isHidden = false
        XCTAssertNotNil(view.spriteLayer.animationKeys())
        configure(reduced: true)
        XCTAssertNil(view.spriteLayer.animationKeys())
        XCTAssertTrue(view.spriteLayer.contents as AnyObject? === atlas.images(for: .wave)?.first)
        configure(enabled: false)
        XCTAssertNil(view.spriteLayer.animationKeys())
        configure()
        XCTAssertNil(view.spriteLayer.animationKeys(), "Motion toggles must not replay one-shot events")
        view.configure(atlas: atlas, state: .idle, session: session)
        XCTAssertNotNil(view.spriteLayer.animationKeys())
        panel.orderOut(nil)
        for _ in 0..<20 {
            NSApp.updateWindows()
            CATransaction.flush()
            if !panel.occlusionState.contains(.visible) { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        XCTAssertFalse(panel.occlusionState.contains(.visible))
        XCTAssertNil(view.spriteLayer.animationKeys(), "Occluded windows must release playback")
        panel.orderFrontRegardless()
        for _ in 0..<20 {
            NSApp.updateWindows()
            CATransaction.flush()
            if panel.occlusionState.contains(.visible) { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        XCTAssertNotNil(view.spriteLayer.animationKeys())
        view.frame.size = .zero
        view.layout()
        XCTAssertNil(view.spriteLayer.animationKeys(), "Zero-sized surfaces cannot schedule playback")
        view.frame.size = CGSize(width: 40, height: 60)
        view.layout()
        XCTAssertNotNil(view.spriteLayer.animationKeys())
        panel.contentView = nil
        XCTAssertNil(view.spriteLayer.animationKeys())
        view.configure(atlas: atlas, state: .idle, session: session)
        XCTAssertNil(view.spriteLayer.animationKeys(), "A detached native view cannot schedule playback")
    }

    @MainActor
    func testNativeStaticRasterPreservesWholeCellOrientationAtRetinaScale() throws {
        _ = NSApplication.shared
        let atlas = try fixture()
        let view = PetSpriteLayerView(frame: CGRect(x: 0, y: 0, width: 8, height: 12))
        view.configure(atlas: atlas, state: .idle, session: PetSpritePlaybackSession(), animationsEnabled: false)
        view.layout()
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 24, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: 2, y: 2)
        // The full untrimmed source aspect exactly matches this 2x point-size view.
        try XCTUnwrap(view.layer).render(in: context)
        let output = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        let top = try XCTUnwrap(output.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB))
        let bottom = try XCTUnwrap(output.colorAt(x: 14, y: 22)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(top.redComponent, 20.0 / 255, accuracy: 0.01)
        XCTAssertEqual(top.greenComponent, 20.0 / 255, accuracy: 0.01)
        XCTAssertEqual(top.blueComponent, 0, accuracy: 0.01)
        XCTAssertEqual(bottom.blueComponent, 200.0 / 255, accuracy: 0.01)
        XCTAssertEqual(top.alphaComponent, 1)
        XCTAssertEqual(bottom.alphaComponent, 1)
    }

    func testPrecomputedMotionTracksAreBoundedAndReturnToContact() throws {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 200)
        let size = CGSize(width: 96, height: 104)
        let walk = try XCTUnwrap(PetSpriteMotion.walk(distance: 90, duration: 30).track(
            in: rect, spriteSize: size, baseline: 200, startingX: 100))
        XCTAssertEqual(walk.samples.count, 901)
        XCTAssertEqual(walk.keyTimes.count, walk.samples.count)
        XCTAssertEqual(walk.samples.first, walk.samples.last)
        XCTAssertTrue(walk.repeats)
        let jump = try XCTUnwrap(PetSpriteMotion.jump(height: 50, duration: 0.84).track(
            in: rect, spriteSize: size, baseline: 200, startingX: 100))
        XCTAssertLessThanOrEqual(jump.samples.count, 28)
        XCTAssertEqual(jump.samples.first?.bottomContact.x, jump.samples.last?.bottomContact.x)
        XCTAssertEqual(try XCTUnwrap(jump.samples.first?.bottomContact.y),
                       try XCTUnwrap(jump.samples.last?.bottomContact.y), accuracy: 0.00001)
        XCTAssertFalse(jump.repeats)
        XCTAssertNil(PetSpriteMotion.walk(distance: 1, duration: 31).track(
            in: rect, spriteSize: size, baseline: 200, startingX: 100))
    }

    func testBoundedWalkJumpAndStableFloorAcrossPetAndClipChanges() {
        let rect = CGRect(x: 11, y: 17, width: 220, height: 130)
        let motions: [PetSpriteMotion] = [.stationary, .walk(distance: 999, duration: 2),
                                         .walk(distance: -999, duration: 2), .jump(height: 999, duration: 1)]
        for size in [CGSize(width: 40, height: 50), CGSize(width: 60, height: 80), CGSize(width: 999, height: 999)] {
            for motion in motions {
                for index in 0...1000 {
                    let sample = motion.sample(elapsed: Double(index) / 100, in: rect, spriteSize: size,
                                               baseline: rect.maxY, startingX: rect.midX)
                    XCTAssertGreaterThanOrEqual(sample.center.x - sample.size.width / 2, rect.minX - 0.00001)
                    XCTAssertLessThanOrEqual(sample.center.x + sample.size.width / 2, rect.maxX + 0.00001)
                    XCTAssertGreaterThanOrEqual(sample.center.y - sample.size.height / 2, rect.minY - 0.00001)
                    XCTAssertLessThanOrEqual(sample.bottomContact.y, rect.maxY + 0.00001)
                }
            }
            let initial = PetSpriteMotion.jump(height: 60, duration: 1).sample(elapsed: 0, in: rect,
                spriteSize: size, baseline: rect.maxY, startingX: rect.midX)
            let final = PetSpriteMotion.jump(height: 60, duration: 1).sample(elapsed: 1, in: rect,
                spriteSize: size, baseline: rect.maxY, startingX: rect.midX)
            XCTAssertEqual(initial.bottomContact.x, rect.midX)
            XCTAssertEqual(initial.bottomContact.y, rect.maxY)
            XCTAssertEqual(final.bottomContact.y, initial.bottomContact.y, accuracy: 0.00001)
            XCTAssertTrue(final.isGrounded)
        }
        let invalid = PetSpriteMotion.walk(distance: .nan, duration: .nan).sample(elapsed: .infinity,
            in: rect, spriteSize: CGSize(width: CGFloat.infinity, height: CGFloat.nan), baseline: .nan, startingX: .nan)
        XCTAssertTrue(invalid.center.x.isFinite && invalid.center.y.isFinite)
    }
}
