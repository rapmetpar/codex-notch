import AppKit
import Combine

final class CompletionSoundPlayer: ObservableObject {
    static let shared = CompletionSoundPlayer()
    @Published var muted = false

    func play() {
        // Missing audio hardware or sound resources must not affect monitoring.
        guard let sound = NSSound(named: "Tink") else { return }
        sound.volume = 0.25
        sound.play()
    }
}
