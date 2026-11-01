import XCTest
@testable import CodexNotch

final class CodexThreadNavigatorTests: XCTestCase {
    func testOnlyAcceptedThreadLinksCountAsOpened() {
        var fallbackCount = 0
        var requestedURL: URL?
        let succeeds = CodexThreadNavigator(openURL: { requestedURL = $0; return true }, activateApp: {
            fallbackCount += 1
            return true
        })
        XCTAssertTrue(succeeds.open(threadID: "thread"))
        XCTAssertEqual(requestedURL?.absoluteString, "codex://threads/thread")
        XCTAssertEqual(fallbackCount, 0)

        let fails = CodexThreadNavigator(openURL: { _ in false }, activateApp: {
            fallbackCount += 1
            return true
        })
        XCTAssertFalse(fails.open(threadID: "thread"), "Activating Codex must not mark a specific chat viewed")
        XCTAssertFalse(fails.open(threadID: "invalid thread"))
        XCTAssertEqual(fallbackCount, 2)
    }

    func testThreadURLUsesCodexScheme() throws {
        let url = try CodexThreadNavigator.threadURL(id: "019f-test")
        XCTAssertEqual(url.absoluteString, "codex://threads/019f-test")
    }

    func testInvalidThreadIDReturnsNil() {
        XCTAssertNil(CodexThreadNavigator.threadURLIfValid(id: ""))
        XCTAssertNil(CodexThreadNavigator.threadURLIfValid(id: "thread with spaces"))
    }

    func testOnlyCurrentChatGPTCodexBundleIsRecognized() {
        XCTAssertTrue(FrontmostAppMonitor.isChatGPTCodex(bundleIdentifier: "com.openai.codex"))
        XCTAssertFalse(FrontmostAppMonitor.isChatGPTCodex(bundleIdentifier: "com.openai.chatgpt.classic"))
        XCTAssertFalse(FrontmostAppMonitor.isChatGPTCodex(bundleIdentifier: nil))
    }
}
