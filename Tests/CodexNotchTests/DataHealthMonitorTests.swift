import AppKit
import XCTest
@testable import CodexNotch

final class DataHealthMonitorTests: XCTestCase {
    @MainActor
    func testMissingRolloutDirectoryReportsFailureThenEmptyDirectoryRecovers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DataHealth-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions")
        let monitor = RolloutActivityMonitor(rootURL: sessions)
        let model = DataHealth()
        model.start(at: Date())
        defer { monitor.stop(); monitor.onHealthObservation = nil; model.stop() }
        let missing = expectation(description: "missing directory")
        var sawMissing = false
        monitor.onHealthObservation = { observation in
            model.recordRollouts(observation, at: Date())
            if !sawMissing && observation == .failure { sawMissing = true; missing.fulfill() }
        }
        monitor.start()
        await fulfillment(of: [missing], timeout: 3)
        XCTAssertEqual(model.rollouts.state, .unavailable)
        XCTAssertNil(model.rollouts.lastSuccessAt)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let recovered = expectation(description: "empty readable directory")
        var sawRecovery = false
        monitor.onHealthObservation = { observation in
            model.recordRollouts(observation, at: Date())
            if !sawRecovery && observation == .success { sawRecovery = true; recovered.fulfill() }
        }
        monitor.rescan()
        await fulfillment(of: [recovered], timeout: 3)
        XCTAssertEqual(model.rollouts.state, .fresh)
        XCTAssertNotNil(model.rollouts.lastSuccessAt)

        let stopped = expectation(description: "stopped monitor is silent")
        stopped.isInverted = true
        monitor.onHealthObservation = { _ in stopped.fulfill() }
        monitor.stop()
        monitor.rescan()
        await fulfillment(of: [stopped], timeout: 0.2)
    }

    private final class SnapshotReader: NativeThreadReadSnapshotReading {
        private let lock = NSLock()
        private var value: NativeThreadReadSnapshot?
        func set(_ value: NativeThreadReadSnapshot?) { lock.lock(); self.value = value; lock.unlock() }
        func snapshot(for threadIDs: [String]) -> NativeThreadReadSnapshot? {
            lock.lock(); defer { lock.unlock() }; return value
        }
    }

    @MainActor
    func testUnavailableNativeMetadataReportsEvenWithoutReceiptChangesAndNeverOverridesRunning() async {
        let reader = SnapshotReader()
        let model = DataHealth()
        let monitor = NativeConversationReadMonitor(snapshotReader: reader, refreshInterval: 0.02)
        let now = Date()
        let past = now.addingTimeInterval(-30)
        let session = SessionActivity(threadID: "synthetic", turnID: "turn", title: nil, cwd: nil, originator: nil, startedAt: past, lastActivityAt: past)
        let completion = CompletedSession(session: session, completedAt: past)
        model.start(at: now)
        model.recordRollouts(.success, at: now)
        defer { monitor.stop(); monitor.onChange = nil; monitor.onHealthObservation = nil; model.stop() }
        let missing = expectation(description: "unknown native source")
        var sawMissing = false
        monitor.onHealthObservation = { observation in
            model.recordNativeRead(observation, at: Date())
            if !sawMissing && observation == .failure { sawMissing = true; missing.fulfill() }
        }
        monitor.start()
        XCTAssertEqual(model.nativeRead.state, .idle)
        monitor.updateCompletions([completion])
        await fulfillment(of: [missing], timeout: 2)
        XCTAssertEqual(model.nativeRead.state, .unavailable)
        XCTAssertTrue(monitor.receipts.isEmpty)

        let read = expectation(description: "native evidence arrives")
        monitor.onChange = { if monitor.receipts["synthetic"]?.isRead == true { read.fulfill() } }
        reader.set(.init(status: ["synthetic": true], fingerprint: "synthetic-read", modifiedAt: past))
        await fulfillment(of: [read], timeout: 2)
        XCTAssertEqual(model.nativeRead.state, .fresh)
        let successTime = model.nativeRead.lastSuccessAt

        let lost = expectation(description: "native evidence removed")
        monitor.onChange = { if monitor.receipts.isEmpty { lost.fulfill() } }
        reader.set(nil)
        await fulfillment(of: [lost], timeout: 2)
        XCTAssertEqual(model.nativeRead.state, .stale)
        XCTAssertEqual(model.nativeRead.lastSuccessAt, successTime)
        XCTAssertEqual(model.rollouts.state, .fresh)
        func attention(running: Bool) -> ConversationAttention? {
            let input = NotchPresentationInput(now: now, isChatGPTFrontmost: false,
                activeSessions: running ? [session] : [], recentCompletions: [completion], usage: nil,
                isHovered: true, nativeReadReceipts: monitor.receipts)
            guard case .expanded(let content) = NotchPresentationReducer.reduce(input) else { return nil }
            return content.conversations.first?.attention
        }
        XCTAssertEqual(attention(running: true), .running)
        XCTAssertEqual(attention(running: false), .unread)
    }

    @MainActor
    func testStatusWindowIsLazyReusedAndDoesNotUseTheNotchPanel() throws {
        _ = NSApplication.shared
        let domain = "CodexNotch.synthetic.data-health.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("ru", forKey: AppLanguage.storageKey)
        let presenter = DataHealthWindowPresenter()
        XCTAssertNil(presenter.window)
        let window = presenter.windowForPresentation(model: DataHealth(), defaults: defaults)
        defer { window.close() }
        XCTAssertFalse(window is NSPanel)
        XCTAssertEqual(window.level, .normal)
        XCTAssertEqual(window.title, "Состояние данных")
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(window === presenter.windowForPresentation(model: DataHealth(), defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: AppLanguage.storageKey), "ru")
    }
}
