import Foundation
import XCTest
@testable import CodexNotch

final class CompactSignalReplacementTests: XCTestCase {
    func testReplacingFileDoesNotReplayAReadCompletion() async throws {
        try await verifyReplay(deleteFirst: false)
    }

    func testDeletingAndRecreatingFileDoesNotReplayAReadCompletion() async throws {
        try await verifyReplay(deleteFirst: true)
    }

    func testStopStartRejectsQueuedOldCallbackWithoutConsumingCompletion() {
        let gate = CompletionDeliveryGate()
        let old = gate.advance()
        let date = Date()
        let completion = CompletedSession(session: SessionActivity(threadID: "thread", turnID: "turn",
            cwd: nil, originator: nil, startedAt: date, lastActivityAt: date), completedAt: date)
        _ = gate.advance() // stop
        let current = gate.advance() // restart
        XCTAssertNil(gate.claim([completion], generation: old))
        XCTAssertEqual(gate.claim([completion], generation: current), [completion])
        XCTAssertEqual(gate.claim([completion], generation: current), [])
    }

    private func verifyReplay(deleteFirst: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rollout.jsonl")
        let meta = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"thread\",\"source\":\"vscode\"}}\n"
        try Data(meta.utf8).write(to: url)
        let store = ActiveSessionStore()
        let monitor = RolloutActivityMonitor(rootURL: root, store: store)
        let initial = expectation(description: "initial file processed")
        let first = expectation(description: "fresh completion")
        let removed = deleteFirst ? expectation(description: "file removal processed") : nil
        let repeated = expectation(description: "no repeated signal")
        repeated.isInverted = true
        var count = 0
        monitor.onChange = {
            if count == 0 { count = 1; initial.fulfill() }
            else if count == 3 { count = 4; removed?.fulfill() }
        }
        monitor.onNewCompletions = { items in
            guard !items.isEmpty else { return }
            if count == 1 { count = 2; first.fulfill() } else { repeated.fulfill() }
        }
        monitor.start()
        defer { monitor.stop() }
        await fulfillment(of: [initial], timeout: 3)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let contents = meta + "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn\"}}\n" + "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"turn\"}}\n"
        try Data(contents.utf8).write(to: url)
        monitor.filesDidChange([url])
        await fulfillment(of: [first], timeout: 3)
        if deleteFirst {
            count = 3
            try FileManager.default.removeItem(at: url)
            monitor.filesDidChange([url])
            await fulfillment(of: [try XCTUnwrap(removed)], timeout: 3)
        }
        try Data((contents + "\n").utf8).write(to: url, options: .atomic)
        monitor.filesDidChange([url])
        await fulfillment(of: [repeated], timeout: 1)
    }
}
