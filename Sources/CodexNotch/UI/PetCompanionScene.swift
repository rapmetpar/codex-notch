import AppKit
import QuartzCore
import SwiftUI

final class PetCompanionSceneSession {
    let playback = PetSpritePlaybackSession()
    private var motionEvents: Set<String> = []
    func claimMotion(_ token: String) -> Bool {
        guard motionEvents.count < 512 else { return false }
        return motionEvents.insert(token).inserted
    }
}

struct PetCompanionSceneContext {
    let atlas: PetSpriteAtlas
    let name: String
    let pose: PetCompanionPose
    let session: PetCompanionSceneSession
}

private struct PetCompanionContextKey: EnvironmentKey {
    static let defaultValue: PetCompanionSceneContext? = nil
}

extension EnvironmentValues {
    var petCompanionContext: PetCompanionSceneContext? {
        get { self[PetCompanionContextKey.self] }
        set { self[PetCompanionContextKey.self] = newValue }
    }
}

struct PetCompanionScene: View {
    let context: PetCompanionSceneContext
    var compact = false
    @Environment(\.notchMotionEnabled) private var motionEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchAppLanguage) private var language

    var body: some View {
        PetCompanionStage(context: context, compact: compact,
            animationsEnabled: motionEnabled, reduceMotion: reduceMotion)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(context.name)
            .accessibilityValue(status)
    }

    private var status: String {
        switch context.pose {
        case .work:
            return language.localized(chinese: "工作中", english: "Working", russian: "За работой")
        case .celebration:
            return language.localized(chinese: "任务已完成", english: "Task completed", russian: "Задача завершена")
        case .greeting:
            return language.localized(chinese: "打招呼", english: "Greeting", russian: "Приветствие")
        case .idle, .walkLeft, .walkRight:
            return language.localized(chinese: "休息中", english: "At rest", russian: "Отдыхает")
        }
    }
}

struct PetCompanionStage: NSViewRepresentable {
    let context: PetCompanionSceneContext
    let compact: Bool
    let animationsEnabled: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> PetCompanionStageView { PetCompanionStageView(frame: .zero) }
    func updateNSView(_ view: PetCompanionStageView, context: Context) {
        view.configure(scene: self.context, compact: compact,
            animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: PetCompanionStageView, coordinator: ()) { view.dismantle() }
}

/// A bounded native stage. Only child layers move; the panel/canvas never move per frame.
final class PetCompanionStageView: QuotaAnimatedLayerView {
    static let motionKey = "pet.stage.position"
    let sprite = PetSpriteLayerView(frame: .zero)
    private var scene: PetCompanionSceneContext?
    private var compact = false
    private var appEnabled = false
    private var reduceMotion = false
    private var motion: PetSpriteMotion = .stationary
    private var jumpAllowed = false
    private var jumpHasStarted = false
    private var lastSize = CGSize.zero
    private var observer: NSObjectProtocol?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(sprite)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshMotion() }
    }
    required init?(coder: NSCoder) { nil }

    func configure(scene: PetCompanionSceneContext, compact: Bool, animationsEnabled: Bool, reduceMotion: Bool) {
        let changed = self.scene?.pose != scene.pose || self.scene?.atlas !== scene.atlas || self.compact != compact
        if changed { setAnimationRequested(false) }
        if self.scene?.pose != scene.pose || self.scene == nil {
            jumpHasStarted = false
            if case let .celebration(token) = scene.pose { jumpAllowed = scene.session.claimMotion(token) }
            else { jumpAllowed = false }
        }
        self.scene = scene
        self.compact = compact
        self.appEnabled = animationsEnabled
        self.reduceMotion = reduceMotion
        let state: PetSpriteState
        let playback: PetSpritePlayback
        switch scene.pose {
        case .idle: state = .idle; playback = .loop; motion = .stationary
        case .work: state = .workRunning; playback = .loop; motion = .stationary
        case .walkLeft: state = .runLeft; playback = .loop; motion = .walk(distance: -travelDistance, duration: 4)
        case .walkRight: state = .runRight; playback = .loop; motion = .walk(distance: travelDistance, duration: 4)
        case let .greeting(token): state = .wave; playback = .once(token: token); motion = .stationary
        case let .celebration(token):
            state = .jump; playback = .once(token: token)
            motion = .jump(height: compact ? 2 : 20, duration: 0.84)
        }
        sprite.configure(atlas: scene.atlas, state: state, playback: playback, session: scene.session.playback,
            isVisible: true, animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
        refreshMotion()
        needsLayout = true
    }

    private var travelDistance: CGFloat { compact ? 22 : 70 }
    private var motionAllowed: Bool {
        PetCompanionLayout.allowsMotion(appEnabled: appEnabled,
            reduceMotion: reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, visible: true)
    }
    private func refreshMotion() {
        if !motionAllowed { jumpAllowed = false }
        let moves: Bool
        switch motion {
        case .stationary: moves = false
        case .jump: moves = jumpAllowed
        case .walk: moves = true
        }
        let geometryReady = sprite.bounds.width > 0 && sprite.bounds.height > 0
            && bounds.contains(sprite.frame)
        setAnimationRequested(motionAllowed && moves && geometryReady)
    }

    override func layout() {
        super.layout()
        let changedSize = lastSize != bounds.size
        if changedSize { setAnimationRequested(false) }
        let safe = bounds.insetBy(dx: compact ? 3 : 12, dy: 2)
        let height: CGFloat = compact ? max(0, bounds.height - 4) : 72
        let sample = PetSpriteMotion.stationary.sample(elapsed: 0, in: safe,
            spriteSize: CGSize(width: height * 192 / 208, height: height),
            baseline: safe.maxY, startingX: safe.midX)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = CGRect(x: sample.center.x - sample.size.width / 2,
            y: sample.center.y - sample.size.height / 2, width: sample.size.width, height: sample.size.height)
        CATransaction.commit()
        sprite.layoutSubtreeIfNeeded()
        if changedSize {
            lastSize = bounds.size
        }
        refreshMotion()
    }

    override func startLayerAnimation() {
        guard let layer = sprite.layer, layer.animation(forKey: Self.motionKey) == nil else { return }
        switch motion {
        case .stationary: return
        case .walk: break
        case .jump:
            guard !jumpHasStarted else { return }
            jumpHasStarted = true
        }
        let safe = bounds.insetBy(dx: compact ? 3 : 12, dy: 2)
        guard let track = motion.track(in: safe, spriteSize: sprite.bounds.size,
            baseline: safe.maxY, startingX: safe.midX) else { return }
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.values = track.samples.map { NSValue(point: $0.center) }
        animation.keyTimes = track.keyTimes.map { NSNumber(value: $0) }
        animation.duration = track.duration
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        animation.repeatCount = track.repeats ? .infinity : 0
        animation.calculationMode = .linear
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: 30, preferred: 30)
        layer.add(animation, forKey: Self.motionKey)
    }
    override func stopLayerAnimation() { sprite.layer?.removeAnimation(forKey: Self.motionKey) }
    func dismantle() { setAnimationRequested(false); sprite.dismantle() }
    deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
}
