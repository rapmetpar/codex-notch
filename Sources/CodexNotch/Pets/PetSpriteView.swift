import AppKit
import QuartzCore
import SwiftUI

/// Own `session` outside the view (one per scene), especially for one-shot completion events.
struct PetSpriteView: NSViewRepresentable {
    let atlas: PetSpriteAtlas
    let state: PetSpriteState
    var playback: PetSpritePlayback = .loop
    let session: PetSpritePlaybackSession
    var isVisible = true
    var animationsEnabled = true
    var reduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    init(atlas: PetSpriteAtlas, state: PetSpriteState, playback: PetSpritePlayback = .loop,
         session: PetSpritePlaybackSession, isVisible: Bool = true,
         animationsEnabled: Bool = true, reduceMotion: Bool = false) {
        self.atlas = atlas
        self.state = state
        self.playback = playback
        self.session = session
        self.isVisible = isVisible
        self.animationsEnabled = animationsEnabled
        self.reduceMotion = reduceMotion
    }

    func makeNSView(context: Context) -> PetSpriteLayerView {
        let view = PetSpriteLayerView(frame: .zero)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: PetSpriteLayerView, context: Context) {
        view.configure(atlas: atlas, state: state, playback: playback, session: session,
                       isVisible: isVisible, animationsEnabled: animationsEnabled,
                       reduceMotion: reduceMotion || systemReduceMotion)
    }

    static func dismantleNSView(_ view: PetSpriteLayerView, coordinator: ()) { view.dismantle() }
}

/// Discrete native contents animation: zero app timers, zero per-frame SwiftUI state changes.
/// Uses the existing visible-only layer lifecycle; never resizes a window.
final class PetSpriteLayerView: QuotaAnimatedLayerView {
    static let animationKey = "pet.sprite.frames"
    static let maximumFramesPerSecond: Float = 30
    let spriteLayer = CALayer()
    private var atlas: PetSpriteAtlas?
    private var state: PetSpriteState = .idle
    private var playback: PetSpritePlayback = .loop
    private var session: PetSpritePlaybackSession?
    private var callerVisible = false
    private var motionEnabled = false
    private var reduceMotion = false
    private var accessibilityObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        spriteLayer.contentsGravity = .resizeAspect
        spriteLayer.magnificationFilter = .nearest
        spriteLayer.minificationFilter = .nearest
        layer?.addSublayer(spriteLayer)
        setAccessibilityElement(false) // The scene owner supplies the meaningful label.
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshMotionRequest() }
    }

    required init?(coder: NSCoder) { nil }

    func configure(atlas: PetSpriteAtlas, state: PetSpriteState, playback: PetSpritePlayback = .loop,
                   session: PetSpritePlaybackSession, isVisible: Bool = true,
                   animationsEnabled: Bool = true, reduceMotion: Bool = false) {
        let changed = self.atlas !== atlas || self.state != state || self.playback != playback
            || self.session !== session
        if changed { setAnimationRequested(false) }
        self.atlas = atlas
        self.state = state
        self.playback = playback
        self.session = session
        self.callerVisible = isVisible
        self.motionEnabled = animationsEnabled
        self.reduceMotion = reduceMotion
        session.configure(state: state, playback: playback, now: CACurrentMediaTime())
        refreshMotionRequest()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.withoutPetAnimation {
            spriteLayer.frame = bounds
            spriteLayer.contentsScale = window?.backingScaleFactor ?? 1
        }
        refreshMotionRequest()
    }

    private var motionAllowed: Bool {
        motionEnabled && !reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func refreshMotionRequest() {
        guard let clip = atlas?.clips[state], let images = atlas?.images(for: state) else {
            setAnimationRequested(false)
            spriteLayer.contents = nil
            return
        }
        if !motionAllowed { session?.finishOneShot() }
        setAnimationRequested(callerVisible && motionAllowed)
        // A finite animation settles on its final full cell. Motion off always shows the
        // authored static frame, and does not defer a celebration until motion is reenabled.
        let index: Int
        if !motionAllowed { index = clip.staticFrameIndex }
        else if playback == .loop {
            index = clip.frameIndex(at: session?.elapsed(at: CACurrentMediaTime(), duration: clip.duration) ?? 0,
                                   looping: true)
        } else { index = images.count - 1 }
        CATransaction.withoutPetAnimation { spriteLayer.contents = images[index] }
    }

    override func startLayerAnimation() {
        guard spriteLayer.animation(forKey: Self.animationKey) == nil,
              let clip = atlas?.clips[state], let images = atlas?.images(for: state), let session else { return }
        let now = CACurrentMediaTime()
        let elapsed = session.elapsed(at: now, duration: clip.duration)
        guard playback == .loop || elapsed < clip.duration else { return }
        session.resume(at: now)
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = images + [images[images.count - 1]]
        animation.keyTimes = clip.keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .discrete
        animation.duration = clip.duration
        animation.repeatCount = playback == .loop ? .infinity : 0
        let phase = playback == .loop ? elapsed.truncatingRemainder(dividingBy: clip.duration) : elapsed
        animation.beginTime = spriteLayer.convertTime(now, from: nil) - phase
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: Self.maximumFramesPerSecond,
                                                             preferred: Self.maximumFramesPerSecond)
        spriteLayer.add(animation, forKey: Self.animationKey)
    }

    override func stopLayerAnimation() {
        session?.pause(at: CACurrentMediaTime())
        spriteLayer.removeAnimation(forKey: Self.animationKey)
    }

    func dismantle() {
        callerVisible = false
        setAnimationRequested(false)
    }

    deinit {
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }
}

private extension CATransaction {
    static func withoutPetAnimation(_ changes: () -> Void) {
        begin()
        setDisableActions(true)
        changes()
        commit()
    }
}
