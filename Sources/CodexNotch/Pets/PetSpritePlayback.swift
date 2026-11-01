import Foundation

enum PetSpritePlayback: Equatable {
    case loop
    case once(token: String)
}

/// Retain one session per companion scene beyond SwiftUI mounts. Main-thread confined by its owner.
/// This is event identity, not preferences. A bounded, saturated ledger fails closed instead of
/// evicting an old event and replaying it on history reopen. No timers or per-frame observation.
final class PetSpritePlaybackSession {
    static let maximumRememberedEvents = 512
    private var consumed: Set<String> = []
    private var key: String?
    private var playback: PetSpritePlayback = .loop
    private var accumulated: TimeInterval = 0
    private var started: TimeInterval?
    private var terminal = false

    func configure(state: PetSpriteState, playback: PetSpritePlayback, now: TimeInterval) {
        let nextKey: String
        switch playback {
        case .loop: nextKey = "loop:\(state.rawValue)"
        case .once(let token): nextKey = "once:\(token)"
        }
        guard nextKey != key else { return }
        self.playback = playback
        key = nextKey
        accumulated = 0
        started = nil
        terminal = false
        if case .once(let token) = playback {
            terminal = token.isEmpty || token.utf8.count > 256 || consumed.contains(token)
                || consumed.count >= Self.maximumRememberedEvents
            if !terminal { consumed.insert(token) }
        }
    }

    func elapsed(at now: TimeInterval, duration: TimeInterval) -> TimeInterval {
        if terminal { return duration }
        let value = accumulated + (started.map { max(0, now - $0) } ?? 0)
        return playback == .loop ? value : min(duration, value)
    }

    func resume(at now: TimeInterval) { if started == nil && !terminal { started = now } }
    func pause(at now: TimeInterval) {
        if let started { accumulated += max(0, now - started) }
        started = nil
    }
    func finishOneShot() {
        if case .once = playback { terminal = true; started = nil }
    }
}
