import Foundation

/// Main-thread lifecycle; all SQLite work runs on the utility queue. Receipts are
/// refreshed even while rollouts, titles and window focus remain unchanged.
final class NativeConversationReadMonitor {
    static let refreshInterval: TimeInterval = 2
    var onChange: (() -> Void)?
    private(set) var receipts: [String: NativeConversationReadReceipt] = [:]

    private let reader: NativeConversationReadReading
    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "com.david.codexnotch.native-read-receipts", qos: .utility)
    private var timer: Timer?
    private var started = false
    private var inFlight = false
    private var generation: UInt64 = 0
    private var threadIDs: [String] = []

    init(reader: NativeConversationReadReading, refreshInterval: TimeInterval = refreshInterval) {
        self.reader = reader
        self.interval = refreshInterval
    }

    func start() {
        guard !started else { return }
        started = true
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        self.timer = timer
        refresh()
    }

    func stop() {
        started = false
        generation &+= 1
        timer?.invalidate()
        timer = nil
        receipts = [:]
    }

    deinit { timer?.invalidate() }

    func updateThreadIDs(_ ids: [String]) {
        let ids = Array(Set(ids)).sorted()
        guard ids != threadIDs else { return }
        generation &+= 1
        threadIDs = ids
        // Immediately discard acknowledgements for removed conversations.
        receipts = receipts.filter { ids.contains($0.key) }
        refresh()
    }

    private func refresh() {
        guard started, !inFlight else { return }
        guard !threadIDs.isEmpty else {
            if !receipts.isEmpty { receipts = [:]; onChange?() }
            return
        }
        inFlight = true
        let requestGeneration = generation
        let ids = threadIDs
        let reader = reader
        queue.async { [weak self] in
            let resolved = reader.receipts(for: ids)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                guard self.started else { return }
                guard requestGeneration == self.generation else {
                    self.refresh()
                    return
                }
                guard resolved != self.receipts else { return }
                self.receipts = resolved
                self.onChange?()
            }
        }
    }
}
