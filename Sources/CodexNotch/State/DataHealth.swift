import Combine
import Foundation

enum DataHealthState: CaseIterable, Equatable {
    case idle, loading, fresh, stale, unavailable

    func title(language: AppLanguage) -> String {
        switch self {
        case .idle: return language.localized(chinese: "尚未检查", english: "Not checked", russian: "Не проверено")
        case .loading: return language.localized(chinese: "正在检查", english: "Checking", russian: "Проверяется")
        case .fresh: return language.localized(chinese: "已更新", english: "Up to date", russian: "Актуально")
        case .stale: return language.localized(chinese: "可能已过时", english: "May be out of date", russian: "Данные могли устареть")
        case .unavailable: return language.localized(chinese: "不可用", english: "Unavailable", russian: "Недоступно")
        }
    }
}

/// Only allowlisted observations cross from the readers to the status window.
enum DataHealthObservation: Equatable { case idle, success, failure }

struct DataSourceHealth: Equatable {
    private(set) var state: DataHealthState = .idle
    private(set) var lastSuccessAt: Date?
    private(set) var lastCheckFailed = false

    mutating func begin() { state = .loading }
    mutating func pause() { state = .idle }

    mutating func record(_ observation: DataHealthObservation, at now: Date) {
        switch observation {
        case .idle: self = DataSourceHealth()
        case .success:
            lastSuccessAt = now
            lastCheckFailed = false
            state = .fresh
        case .failure:
            lastCheckFailed = true
            state = lastSuccessAt == nil ? .unavailable : .stale
        }
    }

    func state(at now: Date, staleAfter: TimeInterval) -> DataHealthState {
        if state == .fresh, let lastSuccessAt, now.timeIntervalSince(lastSuccessAt) >= staleAfter {
            return .stale
        }
        return state
    }
}

/// Main-thread UI state. Nothing here is persisted, and errors are never retained.
final class DataHealth: ObservableObject {
    static let shared = DataHealth()
    static let retryInterval: TimeInterval = 10
    static let automaticRefreshInterval: TimeInterval = 60
    static let usageStaleAfter: TimeInterval = 120
    static let rolloutStaleAfter: TimeInterval = 15
    static let nativeReadStaleAfter: TimeInterval = 6

    @Published private(set) var usage = DataSourceHealth()
    @Published private(set) var rollouts = DataSourceHealth()
    @Published private(set) var nativeRead = DataSourceHealth()
    @Published private(set) var usageSnapshot: UsageSnapshot?
    @Published private(set) var now = Date()
    @Published private(set) var isMonitoring = false
    private(set) var lastUsageRequestAt: Date?
    private var requestID: UUID?
    private var usageTask: Task<Void, Never>?
    var onRetry: (() -> Void)?
    var onOpenCodex: (() -> Void)?

    var canRetry: Bool { canRequestUsage(at: now) }

    func start(at now: Date) {
        self.now = now
        isMonitoring = true
        rollouts.begin()
    }

    func stop() {
        // Invalidate first: a cancellation-insensitive client may still return.
        requestID = nil
        usageTask?.cancel()
        usageTask = nil
        isMonitoring = false
        lastUsageRequestAt = nil
        usage.pause()
        rollouts = DataSourceHealth()
        nativeRead = DataSourceHealth()
        onRetry = nil
        onOpenCodex = nil
    }

    deinit { usageTask?.cancel() }

    func updateClock(_ now: Date) { self.now = now }
    func recordRollouts(_ observation: DataHealthObservation, at now: Date) { rollouts.record(observation, at: now) }
    func recordNativeRead(_ observation: DataHealthObservation, at now: Date) { nativeRead.record(observation, at: now) }

    func automaticRefreshIsDue(at now: Date) -> Bool {
        isMonitoring && requestID == nil
            && now.timeIntervalSince(lastUsageRequestAt ?? .distantPast) >= Self.automaticRefreshInterval
    }

    private func canRequestUsage(at now: Date) -> Bool {
        isMonitoring && requestID == nil
            && now.timeIntervalSince(lastUsageRequestAt ?? .distantPast) >= Self.retryInterval
    }

    @discardableResult
    func requestUsage(
        nowProvider: @escaping () -> Date = { .now },
        fetch: @escaping () async throws -> UsageSnapshot,
        didFinish: @escaping () -> Void = {}
    ) -> Bool {
        let now = nowProvider()
        guard canRequestUsage(at: now) else { return false }
        let id = UUID()
        requestID = id
        lastUsageRequestAt = now
        self.now = now
        usage.begin()
        usageTask = Task { [weak self] in
            // Deliberately discard every error, including its localized description.
            let snapshot = try? await fetch()
            await MainActor.run { [weak self] in
                guard let self, self.requestID == id, self.isMonitoring else { return }
                self.requestID = nil
                self.usageTask = nil
                self.now = nowProvider()
                if let snapshot {
                    self.usageSnapshot = snapshot
                    self.usage.record(.success, at: snapshot.fetchedAt)
                } else {
                    self.usage.record(.failure, at: self.now)
                }
                didFinish()
            }
        }
        return true
    }
}

enum DataHealthText {
    static func title(_ language: AppLanguage) -> String {
        language.localized(chinese: "数据状态", english: "Data Status", russian: "Состояние данных")
    }

    static func lastSuccess(_ date: Date?, language: AppLanguage) -> String {
        guard let date else {
            return language.localized(chinese: "尚无成功检查", english: "No successful check yet", russian: "Успешных проверок пока нет")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let value = formatter.string(from: date)
        return language.localized(chinese: "上次成功检查：\(value)", english: "Last successful check: \(value)", russian: "Последняя успешная проверка: \(value)")
    }

    static func failure(_ language: AppLanguage) -> String {
        language.localized(chinese: "上次检查失败。", english: "The last check failed.", russian: "Последняя проверка не удалась.")
    }
}
