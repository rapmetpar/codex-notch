import AppKit
import CoreGraphics

/// The stored UUID is opaque and is never shown in Settings or logs.
enum DisplaySelection {
    static let storageKey = "selectedDisplayUUID"
    static let automatic = ""

    struct Display: Equatable {
        let identity: String
        let drawableID: CGDirectDisplayID
    }

    static func select(_ preference: String, displays: [Display], availableIDs: [CGDirectDisplayID], autoID: CGDirectDisplayID?) -> CGDirectDisplayID? {
        if !preference.isEmpty,
           let selected = displays.first(where: { $0.identity == preference }),
           availableIDs.contains(selected.drawableID) {
            return selected.drawableID
        }
        return autoID
    }

    static func screenID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func identity(_ id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func onlineDisplays() -> [Display] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).compactMap { id in
            guard let identity = identity(id) else { return nil }
            let master = CGDisplayMirrorsDisplay(id)
            return Display(identity: identity, drawableID: master == kCGNullDirectDisplay ? id : master)
        }
    }
}
