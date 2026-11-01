import Foundation

/// One app-owned domain for packaged apps and unbundled development launches.
/// Keep this identical to the released CFBundleIdentifier: existing choices
/// already live here, so no copy/migration (or reset-resurrecting marker) is needed.
enum AppPreferences {
    static let domain = "com.david.codexnotch"
    static let store = makeStore(domain: domain)

    /// Explicit injection for isolated callers/guards; never derive identity
    /// from a bundle path, worktree, executable name or current version.
    static func makeStore(domain: String) -> UserDefaults {
        // Foundation rejects suiteName equal to the current bundle identifier.
        // In a released .app, standard already owns precisely this domain.
        if Bundle.main.bundleIdentifier == domain { return .standard }
        guard let store = UserDefaults(suiteName: domain) else {
            preconditionFailure("Cannot open the app preference domain")
        }
        return store
    }
}
