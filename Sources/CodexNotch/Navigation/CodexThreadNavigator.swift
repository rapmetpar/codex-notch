import AppKit
import Foundation

enum CodexThreadNavigationError: Error, Equatable {
    case invalidThreadID
}

enum ThreadHandoffResult: Equatable {
    case accepted, invalidID, refused, appUnavailable
}

struct CodexThreadNavigator {
    private let openURL: (URL) -> Bool
    private let activateApp: () -> Bool
    private let isAppAvailable: () -> Bool

    init(workspace: NSWorkspace = .shared) {
        openURL = { workspace.open($0) }
        isAppAvailable = { workspace.urlForApplication(withBundleIdentifier: AppIdentity.chatGPTCodexBundleIdentifier) != nil }
        activateApp = {
            guard let appURL = workspace.urlForApplication(
                withBundleIdentifier: AppIdentity.chatGPTCodexBundleIdentifier
            ) else { return false }
            return workspace.open(appURL)
        }
    }

    init(openURL: @escaping (URL) -> Bool, activateApp: @escaping () -> Bool, isAppAvailable: @escaping () -> Bool = { true }) {
        self.openURL = openURL
        self.activateApp = activateApp
        self.isAppAvailable = isAppAvailable
    }

    static func threadURL(id: String) throws -> URL {
        guard !id.isEmpty,
              id.unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.alphanumerics.contains(scalar)
                      || scalar == "-"
                      || scalar == "_"
                      || scalar == "."
              }) else {
            throw CodexThreadNavigationError.invalidThreadID
        }

        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(id)"
        guard let url = components.url else {
            throw CodexThreadNavigationError.invalidThreadID
        }
        return url
    }

    static func threadURLIfValid(id: String) -> URL? {
        try? threadURL(id: id)
    }

    func handoff(threadID: String) -> ThreadHandoffResult {
        guard let url = Self.threadURLIfValid(id: threadID) else { return .invalidID }
        guard isAppAvailable() else { return .appUnavailable }
        return openURL(url) ? .accepted : .refused
    }

    @discardableResult
    func open(threadID: String) -> Bool {
        if let url = Self.threadURLIfValid(id: threadID), openURL(url) {
            return true
        }
        _ = activateCodex()
        // An app-level fallback cannot acknowledge a specific conversation.
        return false
    }

    @discardableResult
    func activateCodex() -> Bool {
        activateApp()
    }
}
