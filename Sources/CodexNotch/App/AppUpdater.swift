import AppKit
import Combine

/// Manual-only releases: never start an updater, download, or install an archive.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    static let releaseURL = URL(string: "https://github.com/rapmetpar/codex-notch/releases/latest")!

    @Published private(set) var canCheckForUpdates = true
    @Published private(set) var startupError: String?
    private let openURL: (URL) -> Bool

    init(openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.openURL = openURL
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        startupError = openURL(Self.releaseURL) ? nil : "Could not open the releases page."
    }
}
