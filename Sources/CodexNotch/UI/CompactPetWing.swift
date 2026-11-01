import AppKit
import QuartzCore
import SwiftUI

/// The original 46pt lane stays unchanged. Whole pet cells fit inside the
/// same centered slot as quota/check and outside the physical camera.
enum CompactPetWingLayout {
    static let slotWidth: CGFloat = 26
    static func petHeight(in header: CGFloat) -> CGFloat { min(28, header) }
}

enum CompactPetSlotContent: Equatable { case pet, fiveHour, completed }

/// A low-cadence schedule, independent of the app's one-second clock updates.
struct CompactPetSlotCycle: Equatable {
    static let hold: TimeInterval = 4.5
    static let fade: TimeInterval = 0.35
    let contents: [CompactPetSlotContent]

    init(hasFiveHour: Bool, activity: QuotaRingActivity) {
        contents = [.pet] + (hasFiveHour ? [.fiveHour] : []) + (activity == .completed ? [.completed] : [])
    }
    var staticContent: CompactPetSlotContent {
        contents.contains(.fiveHour) ? .fiveHour : (contents.contains(.completed) ? .completed : .pet)
    }
    struct Sample: Equatable {
        let current: CompactPetSlotContent
        let next: CompactPetSlotContent?
        let fadeProgress: Double
        let nextBoundary: TimeInterval?
    }
    func sample(elapsed: TimeInterval) -> Sample {
        guard contents.count > 1 else {
            return Sample(current: .pet, next: nil, fadeProgress: 0, nextBoundary: nil)
        }
        let step = Self.hold + Self.fade
        let time = max(0, elapsed).truncatingRemainder(dividingBy: step * Double(contents.count))
        let index = min(contents.count - 1, Int(time / step))
        let local = time - Double(index) * step
        if local < Self.hold {
            return Sample(current: contents[index], next: nil, fadeProgress: 0, nextBoundary: Self.hold - local)
        }
        return Sample(current: contents[index], next: contents[(index + 1) % contents.count],
            fadeProgress: (local - Self.hold) / Self.fade, nextBoundary: step - local)
    }
}

enum CompactPetSlotSemantics {
    static func state(_ activity: QuotaRingActivity, language: AppLanguage) -> String {
        switch activity {
        case .running: return language.localized(chinese: "运行中", english: "Running", russian: "В работе")
        case .completed: return language.localized(chinese: "已完成", english: "Completed", russian: "Завершено")
        case .idle: return language.localized(chinese: "就绪", english: "Ready", russian: "Готов")
        }
    }
}

struct CompactPetWing: View {
    let context: PetCompanionSceneContext
    let activity: QuotaRingActivity
    let fiveHour: UsageWindow?
    let quotaStyle: QuotaDisplayStyle
    let compactHeight: CGFloat
    @Environment(\.notchMotionEnabled) private var motionEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.quotaAppearance) private var appearance

    var body: some View {
        CompactPetSlot(context: context, activity: activity, fiveHour: fiveHour,
            quotaStyle: quotaStyle, appearance: appearance,
            animationsEnabled: motionEnabled, reduceMotion: reduceMotion)
            .frame(width: CompactPetWingLayout.slotWidth, height: CompactPetWingLayout.petHeight(in: compactHeight))
            .allowsHitTesting(false)
            .accessibilityHidden(true) // The unchanged enclosing button names task + all real quotas.
    }
}

struct CompactPetSlot: NSViewRepresentable {
    let context: PetCompanionSceneContext
    let activity: QuotaRingActivity
    let fiveHour: UsageWindow?
    let quotaStyle: QuotaDisplayStyle
    let appearance: QuotaAppearance
    let animationsEnabled: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> CompactPetSlotView { CompactPetSlotView(frame: .zero) }
    func updateNSView(_ view: CompactPetSlotView, context: Context) {
        view.configure(scene: self.context, activity: activity, fiveHour: fiveHour,
            quotaStyle: quotaStyle, appearance: appearance,
            animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: CompactPetSlotView, coordinator: ()) { view.dismantle() }
}

/// Three views occupy exactly one rect. Native opacity handles fades; a single
/// one-shot timer wakes only at hold/fade boundaries, never once per frame.
final class CompactPetSlotView: QuotaAnimatedLayerView {
    static let fadeKey = "compact.slot.fade"
    let pet = PetCompanionStageView(frame: .zero)
    let quota = NSHostingView(rootView: AnyView(Color.clear))
    let completion = CompactPetCompletionView(frame: .zero)
    private(set) var cycle = CompactPetSlotCycle(hasFiveHour: false, activity: .idle)
    private(set) var boundaryTimer: Timer?
    private(set) var visibleContents: [CompactPetSlotContent] = []
    private(set) var elapsed: TimeInterval = 0
    private(set) var startedAt: CFTimeInterval?
    private var scene: PetCompanionSceneContext?
    private var appEnabled = false
    private var reduceMotion = false
    private var lastQuota: UsageWindow?
    private var lastStyle: QuotaDisplayStyle?
    private var lastRenderedHeight: CGFloat = -1
    private var lastAppearance: QuotaAppearance?
    private var observer: NSObjectProtocol?
    var motionAllowed: Bool {
        appEnabled && !reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        quota.sizingOptions = []
        for view in [pet, quota, completion] as [NSView] {
            view.wantsLayer = true
            addSubview(view)
        }
        setAccessibilityElement(false)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshMotion() }
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(scene: PetCompanionSceneContext, activity: QuotaRingActivity, fiveHour: UsageWindow?,
                   quotaStyle: QuotaDisplayStyle, appearance: QuotaAppearance,
                   animationsEnabled: Bool, reduceMotion: Bool) {
        let nextCycle = CompactPetSlotCycle(hasFiveHour: fiveHour != nil, activity: activity)
        let cycleChanged = cycle != nextCycle
        if cycleChanged {
            setAnimationRequested(false)
            cycle = nextCycle
            elapsed = 0
        }
        self.scene = scene
        self.appEnabled = animationsEnabled
        self.reduceMotion = reduceMotion
        if lastQuota != fiveHour || lastStyle != quotaStyle || lastAppearance != appearance {
            lastQuota = fiveHour; lastStyle = quotaStyle; lastAppearance = appearance
            lastRenderedHeight = -1
        }
        refreshQuota()
        refreshMotion()
        needsLayout = true
    }

    private func refreshQuota() {
        guard lastRenderedHeight != bounds.height, let style = lastStyle, let appearance = lastAppearance else { return }
        lastRenderedHeight = bounds.height
        // Static real quota pixels: no blue spinner/halo and no hidden
        // quota animation burning work behind another phase.
        quota.rootView = AnyView(CompactQuotaView(window: lastQuota, activity: .idle,
                style: style, layoutMode: .notch, laneWidth: CompactPetWingLayout.slotWidth,
                compactHeight: CompactPetWingLayout.petHeight(in: bounds.height))
                .environment(\.quotaAppearance, appearance).environment(\.notchMotionEnabled, false))
    }

    override func layout() {
        super.layout()
        withoutSlotActions {
            for view in [pet, quota, completion] as [NSView] { view.frame = bounds }
        }
        refreshQuota()
        for view in [pet, quota, completion] as [NSView] { view.layoutSubtreeIfNeeded() }
        refreshMotion()
    }

    private func refreshMotion() {
        setAnimationRequested(motionAllowed && cycle.contents.count > 1)
        if !motionAllowed {
            showStatic(cycle.staticContent)
        } else if !layerAnimationIsRunning {
            render(cycle.sample(elapsed: elapsed), animate: false)
        }
        updatePet()
    }
    private func view(for content: CompactPetSlotContent) -> NSView {
        switch content { case .pet: return pet; case .fiveHour: return quota; case .completed: return completion }
    }
    private func updatePet() {
        guard let scene else { return }
        pet.configure(scene: scene, compact: true,
            animationsEnabled: motionAllowed && visibleContents.contains(.pet), reduceMotion: !motionAllowed)
    }
    private func showStatic(_ content: CompactPetSlotContent) {
        visibleContents = [content]
        withoutSlotActions {
            for item in [CompactPetSlotContent.pet, .fiveHour, .completed] {
                let child = view(for: item)
                child.layer?.removeAnimation(forKey: Self.fadeKey)
                child.isHidden = item != content
                child.layer?.opacity = item == content ? 1 : 0
            }
        }
    }
    private func render(_ sample: CompactPetSlotCycle.Sample, animate: Bool) {
        visibleContents = [sample.current] + (sample.next.map { [$0] } ?? [])
        withoutSlotActions {
            for item in [CompactPetSlotContent.pet, .fiveHour, .completed] {
                let child = view(for: item)
                child.layer?.removeAnimation(forKey: Self.fadeKey)
                child.isHidden = !visibleContents.contains(item)
                let opacity: Float = item == sample.current ? Float(1 - sample.fadeProgress)
                    : (item == sample.next ? Float(sample.fadeProgress) : 0)
                child.layer?.opacity = opacity
                if animate, let layer = child.layer, sample.next != nil, visibleContents.contains(item) {
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = opacity
                    fade.toValue = item == sample.next ? 1 : 0
                    fade.duration = sample.nextBoundary ?? CompactPetSlotCycle.fade
                    fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    fade.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: 30, preferred: 30)
                    layer.opacity = item == sample.next ? 1 : 0
                    layer.add(fade, forKey: Self.fadeKey)
                }
            }
        }
        updatePet()
    }

    override func startLayerAnimation() {
        guard startedAt == nil else { return }
        startedAt = CACurrentMediaTime()
        advanceCycle()
    }
    private func advanceCycle() {
        guard let startedAt else { return }
        let sample = cycle.sample(elapsed: elapsed + CACurrentMediaTime() - startedAt)
        render(sample, animate: true)
        boundaryTimer?.invalidate()
        guard let interval = sample.nextBoundary else { boundaryTimer = nil; return }
        let timer = Timer(timeInterval: max(0.001, interval), repeats: false) { [weak self] _ in self?.advanceCycle() }
        timer.tolerance = 0.015
        boundaryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    override func stopLayerAnimation() {
        if let startedAt { elapsed += max(0, CACurrentMediaTime() - startedAt) }
        startedAt = nil
        boundaryTimer?.invalidate(); boundaryTimer = nil
        render(cycle.sample(elapsed: elapsed), animate: false)
    }
    func dismantle() {
        setAnimationRequested(false)
        boundaryTimer?.invalidate(); boundaryTimer = nil
        pet.dismantle()
    }
    deinit {
        boundaryTimer?.invalidate()
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

/// Only a green check. This view has no running/loading representation.
final class CompactPetCompletionView: NSView {
    private let check = CAShapeLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        check.fillColor = nil
        check.strokeColor = NSColor.systemGreen.cgColor
        check.lineWidth = 2.5
        check.lineCap = .round; check.lineJoin = .round
        layer?.addSublayer(check)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        withoutSlotActions {
            check.frame = bounds
            check.contentsScale = window?.backingScaleFactor ?? 2
            let path = CGMutablePath()
            path.move(to: CGPoint(x: bounds.midX - 6, y: bounds.midY))
            path.addLine(to: CGPoint(x: bounds.midX - 1.5, y: bounds.midY - 4.5))
            path.addLine(to: CGPoint(x: bounds.midX + 6.5, y: bounds.midY + 4.5))
            check.path = path
        }
    }
}

private func withoutSlotActions(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}
