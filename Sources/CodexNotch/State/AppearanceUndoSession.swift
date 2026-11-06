import Foundation
import Combine

/// Volatile, Settings-scoped history. Only explicitly enumerated scalar keys can
/// be written; artwork is observed for conflicts but never stored in history.
final class AppearanceUndoSession: ObservableObject {
    enum Key: CaseIterable {
        case quotaStyle, iconStyle, floatingStyle, animations, customColorEnabled

        var name: String {
            switch self {
            case .quotaStyle: return QuotaDisplayStyle.storageKey
            case .iconStyle: return StatusIconStyle.storageKey
            case .floatingStyle: return FloatingCenterStyle.storageKey
            case .animations: return AppAnimationPreference.storageKey
            case .customColorEnabled: return QuotaAppearance.enabledKey
            }
        }
    }

    enum Value: Equatable {
        case absent, string(String), boolean(Bool), unsupported
    }

    private let store: UserDefaults
    private let manager = UndoManager()
    private var expected: [Key: Value] = [:]
    private var expectedArtwork: Data?
    private var expectedColor: String?

    init(store: UserDefaults = AppPreferences.store) {
        self.store = store
        manager.groupsByEvent = false
        manager.levelsOfUndo = 30
        captureExpected()
    }

    var canUndo: Bool { manager.canUndo }
    var canRedo: Bool { manager.canRedo }

    func set(_ key: Key, to value: Value) {
        guard valid(value, for: key) else { return }
        invalidateIfChanged()
        let old = read(key)
        guard old != value else { return }
        // Corrupt values are never normalized by undo. Allow the explicit new
        // choice but leave no history capable of restoring an unknown type.
        guard old != .unsupported else {
            clear()
            write(value, key: key)
            captureExpected()
            return
        }
        manager.beginUndoGrouping()
        register(key, from: old, to: value)
        write(value, key: key)
        manager.endUndoGrouping()
        captureExpected()
        objectWillChange.send()
    }

    func undo() {
        guard !invalidateIfChanged() else { return }
        manager.undo()
        captureExpected()
        objectWillChange.send()
    }

    func redo() {
        guard !invalidateIfChanged() else { return }
        manager.redo()
        captureExpected()
        objectWillChange.send()
    }

    func clear() {
        manager.removeAllActions()
        captureExpected()
        objectWillChange.send()
    }

    private func register(_ key: Key, from old: Value, to new: Value) {
        manager.registerUndo(withTarget: self) { target in
            target.register(key, from: new, to: old)
            target.write(old, key: key)
        }
    }

    @discardableResult private func invalidateIfChanged() -> Bool {
        guard Key.allCases.contains(where: { read($0) != expected[$0] }) ||
                store.data(forKey: CustomStatusIcon.storageKey) != expectedArtwork ||
                store.string(forKey: QuotaAppearance.colorKey) != expectedColor else { return false }
        clear()
        return true
    }

    private func captureExpected() {
        expected = Dictionary(uniqueKeysWithValues: Key.allCases.map { ($0, read($0)) })
        expectedArtwork = store.data(forKey: CustomStatusIcon.storageKey)
        expectedColor = store.string(forKey: QuotaAppearance.colorKey)
    }

    private func read(_ key: Key) -> Value {
        guard let object = store.object(forKey: key.name) else { return .absent }
        switch key {
        case .animations, .customColorEnabled:
            guard let number = object as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else { return .unsupported }
            return .boolean(number.boolValue)
        default:
            guard let string = object as? String else { return .unsupported }
            return .string(string)
        }
    }

    private func valid(_ value: Value, for key: Key) -> Bool {
        switch (key, value) {
        case (.animations, .boolean), (.customColorEnabled, .boolean), (.quotaStyle, .string), (.iconStyle, .string), (.floatingStyle, .string): return true
        default: return false
        }
    }

    private func write(_ value: Value, key: Key) {
        switch value {
        case .absent: store.removeObject(forKey: key.name)
        case .string(let value): store.set(value, forKey: key.name)
        case .boolean(let value): store.set(value, forKey: key.name)
        case .unsupported: assertionFailure("Unsupported values are never recorded")
        }
    }
}
