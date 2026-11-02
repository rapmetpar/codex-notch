import AppKit
import XCTest
@testable import CodexNotch

final class NativeReadTrackingModeTests: XCTestCase {
    private final class Reader: NativeConversationReadReading {
        private let lock = NSLock()
        private var value: [String: NativeConversationReadReceipt] = ["thread": NativeConversationReadReceipt(turnID: "turn", isRead: false)]
        private var calls = 0
        let initialRead: XCTestExpectation
        init(initialRead: XCTestExpectation) { self.initialRead = initialRead }
        func receipts(for threadIDs: [String]) -> [String: NativeConversationReadReceipt] {
            lock.lock()
            calls += 1
            let first = calls == 1
            let result = value
            lock.unlock()
            if first { initialRead.fulfill() }
            return result
        }
        func setRead() { lock.lock(); value = ["thread": NativeConversationReadReceipt(turnID: "turn")]; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    }

    @MainActor
    func testNativeReadRefreshContinuesWhileRunLoopTracksMouse() {
        let firstRead = expectation(description: "Initial lookup")
        let reader = Reader(initialRead: firstRead)
        let monitor = NativeConversationReadMonitor(reader: reader, refreshInterval: 0.04)
        let initialDelivered = expectation(description: "Initial native evidence applied")
        monitor.onChange = { initialDelivered.fulfill() }
        monitor.updateThreadIDs(["thread"])
        monitor.start()
        defer { monitor.stop(); monitor.onChange = nil }
        wait(for: [firstRead, initialDelivered], timeout: 2)
        let baseline = reader.count
        let changed = expectation(description: "Native read becomes Viewed")
        monitor.onChange = {
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let session = SessionActivity(threadID: "thread", turnID: "turn", cwd: nil, originator: nil,
                startedAt: date, lastActivityAt: date)
            let completion = CompletedSession(session: session, completedAt: date)
            let input = NotchPresentationInput(now: date, isChatGPTFrontmost: false, activeSessions: [],
                recentCompletions: [completion], usage: nil, isHovered: true, nativeReadReceipts: monitor.receipts)
            guard case let .expanded(content) = NotchPresentationReducer.reduce(input) else { return XCTFail("Missing expanded state") }
            XCTAssertTrue(content.conversations.first?.attention == .viewed)
            changed.fulfill()
        }
        reader.setRead()
        let deadline = Date().addingTimeInterval(0.3)
        let keepAlive = Timer(fire: deadline, interval: 0, repeats: false) { _ in }
        RunLoop.current.add(keepAlive, forMode: .eventTracking)
        while Date() < deadline { _ = RunLoop.current.run(mode: .eventTracking, before: deadline) }
        XCTAssertGreaterThan(reader.count, baseline, "The native reader should refresh while tracking, before returning to default mode")
        wait(for: [changed], timeout: 2)
    }
}
