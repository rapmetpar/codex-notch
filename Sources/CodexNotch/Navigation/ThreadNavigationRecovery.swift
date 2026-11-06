import Foundation

/// Captures the completion once, and never applies its acknowledgement to a later turn.
struct ThreadNavigationRecovery<Identity: Equatable> {
    let handoff: (String) -> ThreadHandoffResult
    let currentTurn: (String) -> Identity?
    let acknowledge: (String, Identity) -> Void
    let showFailure: (String, ThreadHandoffResult, Identity?) -> Void

    func open(threadID: String) {
        retry(threadID: threadID, capturedTurn: currentTurn(threadID))
    }

    func retry(threadID: String, capturedTurn: Identity?) {
        let result = handoff(threadID)
        guard result == .accepted else {
            showFailure(threadID, result, capturedTurn)
            return
        }
        if let capturedTurn, currentTurn(threadID) == capturedTurn {
            acknowledge(threadID, capturedTurn)
        }
    }
}
