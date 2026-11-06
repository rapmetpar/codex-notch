import Foundation
import Combine

/// Memory-only comparison of already fetched snapshots; it never starts a request.
final class QuotaCheckpoint: ObservableObject {
    static let freshnessLimit: TimeInterval = 120
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var baseline: UsageSnapshot?
    @Published private(set) var startedAt: Date?
    @Published private(set) var lastRefreshFailed = false

    enum Comparison: Equatable {
        case noCheckpoint, stale, unavailable, incomparable, change(Double)
    }

    func update(_ snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        lastRefreshFailed = false
    }

    func failed() { lastRefreshFailed = true }

    func start(now: Date) {
        guard let snapshot, isFresh(snapshot, now: now), !lastRefreshFailed else { return }
        baseline = snapshot
        startedAt = now
    }

    func clear() { baseline = nil; startedAt = nil }
    func stop() { clear(); snapshot = nil; lastRefreshFailed = false }

    func isFresh(_ snapshot: UsageSnapshot, now: Date) -> Bool {
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        return age >= 0 && age <= Self.freshnessLimit
    }

    func comparison(kind: UsageWindowKind, now: Date) -> Comparison {
        guard let baseline else { return .noCheckpoint }
        guard let snapshot else { return .unavailable }
        guard !lastRefreshFailed, isFresh(snapshot, now: now) else { return .stale }
        guard snapshot.fetchedAt >= baseline.fetchedAt else { return .incomparable }
        guard let old = baseline.windows.first(where: { $0.kind == kind }),
              let current = snapshot.windows.first(where: { $0.kind == kind }) else { return .unavailable }
        guard let reset = old.resetAt, let currentReset = current.resetAt,
              old.id == current.id, reset == currentReset, now < reset,
              current.remainingPercent <= old.remainingPercent else { return .incomparable }
        return .change(current.remainingPercent - old.remainingPercent)
    }
}
