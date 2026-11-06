import Foundation

/// Consumes only the monitor's live successful events, never presentation state.
final class CompletionSoundPolicy {
    static let storageKey = "completionSoundEnabled"
    private var seen = Set<PetCompletionKey>()
    private var order: [PetCompletionKey] = []
    private var lastPlayed: TimeInterval?
    private var running = false
    private let play: () -> Void

    init(play: @escaping () -> Void) { self.play = play }

    func start() {
        seen.removeAll()
        order.removeAll()
        lastPlayed = nil
        running = true
    }

    func stop() { running = false }

    func receive(_ completions: [CompletedSession], enabled: Bool, muted: Bool, uptime: TimeInterval) {
        guard running else { return }
        var fresh = false
        for completion in completions {
            let key = PetCompletionKey(completion)
            if seen.insert(key).inserted {
                order.append(key)
                fresh = true
            }
        }
        if order.count > 512 {
            let count = order.count - 512
            for key in order.prefix(count) { seen.remove(key) }
            order.removeFirst(count)
        }
        guard fresh, enabled, !muted else { return }
        if let lastPlayed, uptime - lastPlayed < 10 { return }
        lastPlayed = uptime
        play()
    }
}
