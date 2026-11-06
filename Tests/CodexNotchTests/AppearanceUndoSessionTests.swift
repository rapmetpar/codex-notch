import XCTest
@testable import CodexNotch

final class AppearanceUndoSessionTests: XCTestCase {
    private func withStore(_ body: (UserDefaults, AppearanceUndoSession) -> Void) {
        let domain = "CodexNotch.synthetic.undo.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: domain)!
        defer { store.removePersistentDomain(forName: domain) }
        body(store, AppearanceUndoSession(store: store))
    }

    func testThreeChoicesUndoRedoWithExactValuesAndOtherPreferencesUntouched() {
        withStore { store, history in
            store.set("future-style", forKey: QuotaDisplayStyle.storageKey)
            store.set(false, forKey: AppAnimationPreference.storageKey)
            store.set(0, forKey: RecentConversationLimit.storageKey)
            store.set("keep", forKey: "unknown-key")
            history.clear()
            history.set(.quotaStyle, to: .string("waveBall"))
            history.set(.animations, to: .boolean(true))
            history.set(.floatingStyle, to: .string("test-style"))
            history.undo()
            XCTAssertNil(store.object(forKey: FloatingCenterStyle.storageKey))
            history.undo()
            XCTAssertEqual(store.object(forKey: AppAnimationPreference.storageKey) as? Bool, false)
            history.undo()
            XCTAssertEqual(store.string(forKey: QuotaDisplayStyle.storageKey), "future-style")
            XCTAssertFalse(history.canUndo)
            history.redo(); history.redo(); history.redo()
            XCTAssertEqual(store.string(forKey: QuotaDisplayStyle.storageKey), "waveBall")
            XCTAssertEqual(store.object(forKey: AppAnimationPreference.storageKey) as? Bool, true)
            XCTAssertEqual(store.string(forKey: FloatingCenterStyle.storageKey), "test-style")
            XCTAssertEqual(store.integer(forKey: RecentConversationLimit.storageKey), 0)
            XCTAssertEqual(store.string(forKey: "unknown-key"), "keep")
        }
    }

    func testExternalEditInvalidatesHistoryWithoutOverwritingAndNewChangeStartsFresh() {
        withStore { store, history in
            history.set(.quotaStyle, to: .string("waveBall"))
            store.set("external", forKey: QuotaDisplayStyle.storageKey)
            history.undo()
            XCTAssertEqual(store.string(forKey: QuotaDisplayStyle.storageKey), "external")
            XCTAssertFalse(history.canUndo)
            history.set(.quotaStyle, to: .string("next"))
            history.undo()
            XCTAssertEqual(store.string(forKey: QuotaDisplayStyle.storageKey), "external")
        }
    }

    func testArtworkChangeInvalidatesAndClearEndsSession() {
        withStore { store, history in
            history.set(.iconStyle, to: .string("custom"))
            store.set(Data([1, 2]), forKey: CustomStatusIcon.storageKey)
            history.undo()
            XCTAssertEqual(store.string(forKey: StatusIconStyle.storageKey), "custom")
            XCTAssertEqual(store.data(forKey: CustomStatusIcon.storageKey), Data([1, 2]))
            history.set(.animations, to: .boolean(false))
            history.clear()
            XCTAssertFalse(history.canUndo)
            XCTAssertFalse(history.canRedo)
            XCTAssertFalse(AppearanceUndoSession(store: store).canUndo)
        }
    }

    func testColorSwitchIsUndoableButExternalColorChangeInvalidatesIt() {
        withStore { store, history in
            history.set(.customColorEnabled, to: .boolean(true))
            history.undo()
            XCTAssertNil(store.object(forKey: QuotaAppearance.enabledKey))
            history.redo()
            XCTAssertEqual(store.object(forKey: QuotaAppearance.enabledKey) as? Bool, true)
            store.set("#123456", forKey: QuotaAppearance.colorKey)
            history.undo()
            XCTAssertEqual(store.object(forKey: QuotaAppearance.enabledKey) as? Bool, true)
            XCTAssertEqual(store.string(forKey: QuotaAppearance.colorKey), "#123456")
            XCTAssertFalse(history.canUndo)
        }
    }

    func testBoundAndNewEditClearsRedo() {
        withStore { store, history in
            for n in 0..<35 { history.set(.quotaStyle, to: .string("value\(n)")) }
            for _ in 0..<35 { history.undo() }
            XCTAssertEqual(store.string(forKey: QuotaDisplayStyle.storageKey), "value4")
            XCTAssertFalse(history.canUndo)
            XCTAssertTrue(history.canRedo)
            history.set(.animations, to: .boolean(false))
            XCTAssertFalse(history.canRedo)
        }
    }

    func testWrongTypedInputAndCorruptPriorValueDoNotCreateUndo() {
        withStore { store, history in
            history.set(.animations, to: .string("false"))
            XCTAssertNil(store.object(forKey: AppAnimationPreference.storageKey))
            store.set(Data([9]), forKey: QuotaDisplayStyle.storageKey)
            history.set(.quotaStyle, to: .string("waveBall"))
            XCTAssertEqual(store.string(forKey: QuotaDisplayStyle.storageKey), "waveBall")
            XCTAssertFalse(history.canUndo)
        }
    }
}
