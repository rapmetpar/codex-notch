import Foundation

enum NotchActivationMode: String, Sendable {
    case hover, click
    static let storageKey = "notchActivationMode"
    static func read(from defaults: UserDefaults) -> Self {
        defaults.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .hover
    }
}

/// Explicit disclosure never treats pointer movement as an open or close.
struct NotchClickActivation {
    private(set) var isOpen = false
    enum Event { case pointerMoved, toggle, dismiss }
    mutating func send(_ event: Event) {
        switch event {
        case .pointerMoved: break
        case .toggle: isOpen.toggle()
        case .dismiss: isOpen = false
        }
    }
}
