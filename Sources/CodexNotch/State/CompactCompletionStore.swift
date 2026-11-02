import Foundation

/// Bounded signals for completions observed while the monitor was running.
/// Identifiers and timestamps only; never store conversation content.
final class CompactCompletionStore {
    static let storageKey = "compactCompletionSignals.v1"
    static let maximumSignals = 512
    private let defaults: UserDefaults
    private(set) var signals: [String: ConversationReadReceipt]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        signals = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: ConversationReadReceipt].self, from: $0) } ?? [:]
    }

    func record(_ completions: [CompletedSession]) {
        guard !completions.isEmpty else { return }
        for completion in completions {
            signals[completion.session.threadID] = ConversationReadReceipt(completion)
        }
        if signals.count > Self.maximumSignals {
            signals = Dictionary(uniqueKeysWithValues: signals.sorted {
                if $0.value.completedAt == $1.value.completedAt { return $0.key < $1.key }
                return $0.value.completedAt > $1.value.completedAt
            }.prefix(Self.maximumSignals).map { ($0.key, $0.value) })
        }
        persist()
    }

    func removeViewed(local: [String: ConversationReadReceipt], native: [String: NativeConversationReadReceipt]) {
        let previous = signals
        signals = signals.filter { threadID, signal in
            local[threadID] != signal && !(native[threadID]?.turnID == signal.turnID && native[threadID]?.isRead == true)
        }
        if previous != signals { persist() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(signals) { defaults.set(data, forKey: Self.storageKey) }
    }
}
