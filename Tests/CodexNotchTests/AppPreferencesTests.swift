import AppKit

import XCTest
@testable import CodexNotch

final class AppPreferencesTests: XCTestCase {
    func testReleasedIdentityAndEveryProductionEntryPointUseTheSameStore() throws {
        XCTAssertEqual(AppPreferences.domain, AppIdentity.bundleIdentifier)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path))
        }
        let app = try source("Sources/CodexNotch/App/CodexNotchApp.swift")
        XCTAssertTrue(app.contains("@AppStorage(AppLanguage.storageKey, store: AppPreferences.store)"))
        XCTAssertTrue(app.contains(".defaultAppStorage(AppPreferences.store)"))
        let runtime = try source("Sources/CodexNotch/App/NotchRuntimeCoordinator.swift")
        XCTAssertTrue(runtime.contains("userDefaults: UserDefaults = AppPreferences.store"))
        XCTAssertTrue(runtime.contains(".defaultAppStorage(userDefaults)"))
        let window = try source("Sources/CodexNotch/Window/NotchWindowController.swift")
        XCTAssertFalse(window.contains("UserDefaults.standard"))
    }

    func testOpeningPreservesFalseZeroCustomPixelsFutureKeysAndExplicitReset() throws {
        let domain = "CodexNotch.synthetic.preferences.\(UUID().uuidString)"
        let first = AppPreferences.makeStore(domain: domain)
        defer { first.removePersistentDomain(forName: domain) }
        let image = try CustomStatusIcon.normalizedPNG(from: XCTUnwrap(NSImage(
            size: NSSize(width: 2, height: 2), flipped: false, drawingHandler: { rect in
                NSColor.red.setFill(); rect.fill(); return true
            }).tiffRepresentation))
        first.set("ru", forKey: AppLanguage.storageKey)
        first.set(0, forKey: RecentConversationLimit.storageKey)
        first.set(false, forKey: AppAnimationPreference.storageKey)
        first.set(false, forKey: NotchDisplayPreference.storageKey)
        first.set(image, forKey: CustomStatusIcon.storageKey)
        first.set("keep", forKey: "future.v99")
        let before = try XCTUnwrap(first.persistentDomain(forName: domain)) as NSDictionary
        let reopened = AppPreferences.makeStore(domain: domain)
        XCTAssertEqual(reopened.persistentDomain(forName: domain)! as NSDictionary, before)
        let preferences = NotchRuntimePreferences.read(from: reopened)
        XCTAssertEqual(preferences.language, .russian)
        XCTAssertEqual(preferences.recentConversationLimit, .none)
        XCTAssertFalse(preferences.animationsEnabled)
        XCTAssertFalse(preferences.notchDisplayEnabled)
        XCTAssertNotNil(CustomStatusIcon.image(from: reopened.data(forKey: CustomStatusIcon.storageKey)!))
        reopened.removePersistentDomain(forName: domain)
        let reset = AppPreferences.makeStore(domain: domain)
        XCTAssertNil(reset.object(forKey: "future.v99"))
        XCTAssertEqual(NotchRuntimePreferences.read(from: reset).language, .english)
    }

    func testCorruptValuesFallbackWithoutMutatingStoredDataOrOtherDomains() {
        let domain = "CodexNotch.synthetic.preferences.\(UUID().uuidString)"
        let otherDomain = domain + ".other"
        let store = AppPreferences.makeStore(domain: domain)
        let other = AppPreferences.makeStore(domain: otherDomain)
        defer {
            store.removePersistentDomain(forName: domain)
            other.removePersistentDomain(forName: otherDomain)
        }
        other.set("ru", forKey: AppLanguage.storageKey)
        store.set("unknown-language", forKey: AppLanguage.storageKey)
        store.set(-100, forKey: RecentConversationLimit.storageKey)
        store.set(Data([0, 255]), forKey: CustomStatusIcon.storageKey)
        let read = NotchRuntimePreferences.read(from: AppPreferences.makeStore(domain: domain))
        XCTAssertEqual(read.language, .english)
        XCTAssertEqual(read.recentConversationLimit, .two)
        XCTAssertNil(CustomStatusIcon.image(from: store.data(forKey: CustomStatusIcon.storageKey)!))
        XCTAssertEqual(store.string(forKey: AppLanguage.storageKey), "unknown-language")
        XCTAssertEqual(other.string(forKey: AppLanguage.storageKey), "ru")
    }
}
