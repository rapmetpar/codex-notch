import Foundation
import CryptoKit

/// Presentation-only events. Neither visibility nor greeting changes chat read state.
enum PetCompanionPose: Equatable {
    case idle, work, walkRight, walkLeft
    case greeting(token: String), celebration(token: String)
}

struct PetCompletionKey: Hashable {
    let threadID: String
    let turnID: String
    let completedAt: Date

    init(_ completion: CompletedSession) {
        threadID = completion.session.threadID
        turnID = completion.session.turnID
        completedAt = completion.completedAt
    }

    var token: String {
        // IDs are local metadata only; never written to preferences or artwork.
        let identity = "\(threadID)\u{0}\(turnID)\u{0}\(completedAt.timeIntervalSince1970)"
        return "completion:" + SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct PetCompanionPolicy {
    static let greetingCooldown: TimeInterval = 30
    static let eventLifetime: TimeInterval = 1.5
    private var observedAt: Date?
    private var startedAt: Date?
    private var seenCompletions: [PetCompletionKey] = []
    private var lastGreeting: Date?
    private var wasHovered = false
    private var transient: (pose: PetCompanionPose, expiresAt: Date)?
    private(set) var pose: PetCompanionPose = .idle

    mutating func update(
        activeSessions: [SessionActivity], completions: [CompletedSession],
        isHovered: Bool, now: Date
    ) {
        let keys = completions.map(PetCompletionKey.init)
        let previousObservation = observedAt
        if startedAt == nil { startedAt = now }
        // Newly discovered historical logs do not become fresh celebrations.
        let fresh = keys.filter {
            !seenCompletions.contains($0) && previousObservation != nil
        }.filter { key in
            guard let previousObservation else { return false }
            return key.completedAt >= previousObservation && key.completedAt <= now
        }.max { $0.completedAt < $1.completedAt }
        for key in keys where !seenCompletions.contains(key) { seenCompletions.append(key) }
        if seenCompletions.count > 512 { seenCompletions.removeFirst(seenCompletions.count - 512) }
        observedAt = now
        let enteringHover = isHovered && !wasHovered
        wasHovered = isHovered

        // A different active chat remains truthful Running even when another finishes.
        if !activeSessions.isEmpty {
            transient = nil
            pose = .work
            return
        }
        if let fresh {
            transient = (.celebration(token: fresh.token), now.addingTimeInterval(Self.eventLifetime))
        } else if enteringHover,
                  transient == nil || transient!.expiresAt <= now,
                  lastGreeting.map({ now.timeIntervalSince($0) >= Self.greetingCooldown }) ?? true {
            lastGreeting = now
            transient = (.greeting(token: "hover:\(now.timeIntervalSince1970)"), now.addingTimeInterval(Self.eventLifetime))
        }
        if let transient, now < transient.expiresAt {
            pose = transient.pose
        } else {
            transient = nil
            let elapsed = max(0, now.timeIntervalSince(startedAt ?? now))
            let cycle = Int(elapsed / 24)
            let phase = elapsed.truncatingRemainder(dividingBy: 24)
            pose = phase >= 20 ? (cycle.isMultiple(of: 2) ? .walkRight : .walkLeft) : .idle
        }
    }
}

enum PetCompanionLayout {
    static let stageHeight: CGFloat = 104
    static let stageSpacing: CGFloat = 8
    static let expandedHeight: CGFloat = stageHeight + stageSpacing

    static func addingStage(to size: CGSize, enabled: Bool) -> CGSize {
        CGSize(width: size.width, height: size.height + (enabled ? expandedHeight : 0))
    }

    static func showsScene(layout: NotchLayoutMode, expanded: Bool, floatingStyle: FloatingCenterStyle,
                           physicalWingEnabled: Bool = false) -> Bool {
        expanded || (layout == .notch && physicalWingEnabled) || (layout == .floatingBar && floatingStyle == .pet)
    }

    static func allowsMotion(appEnabled: Bool, reduceMotion: Bool, visible: Bool) -> Bool {
        appEnabled && !reduceMotion && visible
    }
}
