import AppKit
import QuartzCore
import SwiftUI

struct ConversationStatusView: View {
    let activity: ConversationActivity
    @Environment(\.notchMotionEnabled) private var motionEnabled

    var body: some View {
        ConversationStatusLayer(isRunning: activity.isRunning, motionEnabled: motionEnabled)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true) // The row's metadata already names its status.
    }
}

private struct ConversationStatusLayer: NSViewRepresentable {
    let isRunning: Bool
    let motionEnabled: Bool

    func makeNSView(context: Context) -> ConversationStatusLayerView {
        let view = ConversationStatusLayerView(frame: .zero)
        view.setAccessibilityElement(false)
        view.configure(isRunning: isRunning, motionEnabled: motionEnabled)
        return view
    }

    func updateNSView(_ view: ConversationStatusLayerView, context: Context) {
        view.configure(isRunning: isRunning, motionEnabled: motionEnabled)
    }

    static func dismantleNSView(_ view: ConversationStatusLayerView, coordinator: ()) {
        view.setAnimationRequested(false)
    }
}

/// A row-local spinner and check; never drives task state or window layout.
final class ConversationStatusLayerView: QuotaAnimatedLayerView {
    private let ring = CAShapeLayer()
    private let check = CAShapeLayer()
    private var isRunning: Bool?
    private var completionPending = false
    private var completionTransitionRequested = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for shape in [ring, check] {
            shape.fillColor = nil
            shape.lineWidth = 1.7
            shape.lineCap = .round
            shape.lineJoin = .round
            layer?.addSublayer(shape)
        }
        configure(isRunning: false, motionEnabled: false)
    }

    required init?(coder: NSCoder) { nil }

    func configure(isRunning: Bool, motionEnabled: Bool) {
        if self.isRunning != isRunning {
            let revealCompletion = self.isRunning == true && !isRunning && motionEnabled
                && window?.isVisible == true
                && window?.occlusionState.contains(.visible) == true
                && !isHiddenOrHasHiddenAncestor
            setAnimationRequested(false)
            self.isRunning = isRunning
            completionPending = revealCompletion
            completionTransitionRequested = revealCompletion
        }
        if !motionEnabled { completionTransitionRequested = false }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let color = isRunning ? NSColor.systemBlue.cgColor : NSColor.systemGreen.cgColor
        ring.strokeColor = color
        ring.strokeEnd = isRunning ? 0.72 : 1
        check.strokeColor = color
        check.isHidden = isRunning
        CATransaction.commit()
        setAnimationRequested(motionEnabled && (isRunning || completionTransitionRequested))
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = min(bounds.width, bounds.height)
        for shape in [ring, check] {
            shape.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            shape.position = CGPoint(x: bounds.midX, y: bounds.midY)
            shape.contentsScale = window?.backingScaleFactor ?? 2
        }
        ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 2, dy: 2), transform: nil)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: side * 0.30, y: side * 0.50))
        path.addLine(to: CGPoint(x: side * 0.44, y: side * 0.35))
        path.addLine(to: CGPoint(x: side * 0.71, y: side * 0.65))
        check.path = path
        CATransaction.commit()
    }

    override func startLayerAnimation() {
        if isRunning == true {
            guard ring.animation(forKey: "conversation.running") == nil else { return }
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = -Double.pi * 2
            rotation.duration = 1.4
            rotation.repeatCount = .infinity
            rotation.preferredFrameRateRange = QuotaLayerAnimationPolicy.frameRateRange
            ring.add(rotation, forKey: "conversation.running")
        } else if completionPending {
            completionPending = false
            let reveal = CABasicAnimation(keyPath: "strokeEnd")
            reveal.fromValue = 0
            reveal.toValue = 1
            reveal.duration = 0.28
            reveal.beginTime = check.convertTime(CACurrentMediaTime(), from: nil)
            reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
            check.add(reveal, forKey: "conversation.completed")
        }
    }

    override func stopLayerAnimation() {
        ring.removeAllAnimations()
        check.removeAllAnimations()
        completionPending = false
    }
}
