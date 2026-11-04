import Foundation
import XCTest
@testable import CodexNotch

final class AppUpdaterConfigurationTests: XCTestCase {
    func testDistributedUpdaterRequiresArchiveVerificationAndNoBackgroundActivity() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        for key in ["SUEnableAutomaticChecks", "SUAutomaticallyUpdate", "SUAllowsAutomaticUpdates", "SUEnableSystemProfiling"] {
            XCTAssertEqual(plist[key] as? Bool, false, key)
        }
        XCTAssertEqual(plist["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(plist["CodexNotchManualUpdatesOnly"] as? Bool, true)
        XCTAssertNil(plist["SUPublicEDKey"])
        XCTAssertNil(plist["SUFeedURL"])
    }

    func testTrackedFeedNeverAdvertisesUpstreamArchives() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let feed = try String(contentsOf: root.appendingPathComponent("appcast.xml"), encoding: .utf8)
        XCTAssertFalse(feed.contains("github.com/fengdwx/codex-notch/releases/"))
    }

    func testSignedPackagingFailsBeforeBuildingOrReadingKeychain() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = root.appendingPathComponent("scripts/release.sh")
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "SIGN_UPDATES": "1"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("signed updates are disabled"))
    }

    @MainActor
    func testManualUpdaterOpensOnlyPersonalReleasePage() {
        var opened: [URL] = []
        let updater = AppUpdater(openURL: { opened.append($0); return true })
        updater.checkForUpdates()
        XCTAssertEqual(opened.map(\.absoluteString), ["https://github.com/rapmetpar/codex-notch/releases/latest"])
        XCTAssertNil(updater.startupError)
    }

    @MainActor
    func testSettingsCanCreateUpdaterWithoutStartingAnUpdateSession() {
        // Creating Settings must not start Sparkle, request permission, or check a feed.
        let updater = AppUpdater()
        XCTAssertTrue(updater.canCheckForUpdates)
        XCTAssertNil(updater.startupError)
    }
}
