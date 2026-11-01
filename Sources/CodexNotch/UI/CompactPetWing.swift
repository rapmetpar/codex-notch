import AppKit
import SwiftUI

enum CompactPetWingLayout {
    static let extraWidth: CGFloat = 42
    static let quotaWidth: CGFloat = 22
    static let statusWidth: CGFloat = 12
    static let petWidth: CGFloat = 30
    static let spacing: CGFloat = 4
    static let padding: CGFloat = 8
    static let laneWidth: CGFloat = 88
    static func petHeight(in header: CGFloat) -> CGFloat { min(28, header) }
}

struct CompactPetWing: View {
    let context: PetCompanionSceneContext
    let activity: QuotaRingActivity
    let compactHeight: CGFloat
    let isExpanded: Bool
    @Environment(\.notchMotionEnabled) private var motionEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: CompactPetWingLayout.spacing) {
            // The caller reserves a separate quota slot before this status/pet pair.
            if activity == .idle {
                Color.clear.frame(width: CompactPetWingLayout.statusWidth, height: CompactPetWingLayout.statusWidth)
            } else {
                CompactPetStatus(activity: activity, motionEnabled: motionEnabled && !reduceMotion)
                    .frame(width: CompactPetWingLayout.statusWidth, height: CompactPetWingLayout.statusWidth)
            }
            Group {
                if isExpanded { Color.clear }
                else { PetCompanionScene(context: context, compact: true) }
            }
            .frame(width: CompactPetWingLayout.petWidth, height: CompactPetWingLayout.petHeight(in: compactHeight))
        }
    }
}

struct CompactPetStatus: NSViewRepresentable {
    let activity: QuotaRingActivity
    let motionEnabled: Bool
    func makeNSView(context: Context) -> CompactPetStatusView { CompactPetStatusView(frame: .zero) }
    func updateNSView(_ view: CompactPetStatusView, context: Context) {
        view.configure(isRunning: activity == .running, motionEnabled: motionEnabled)
    }
    static func dismantleNSView(_ view: CompactPetStatusView, coordinator: ()) { view.status.setAnimationRequested(false) }
}

/// A separate visible state cue, never an inferred pet pose or an unread receipt.
final class CompactPetStatusView: QuotaAnimatedLayerView {
    let status = ConversationStatusLayerView(frame: .zero)
    private var running = false
    private var motion = false
    private var observer: NSObjectProtocol?
    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(status)
        setAccessibilityElement(false) // The enclosing compact button names the task/state.
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }
    required init?(coder: NSCoder) { nil }
    func configure(isRunning: Bool, motionEnabled: Bool) {
        running = isRunning
        motion = motionEnabled
        refresh()
    }
    private func refresh() {
        status.configure(isRunning: running,
            motionEnabled: motion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    override func layout() {
        super.layout()
        status.frame = bounds
        status.layoutSubtreeIfNeeded()
    }
}
