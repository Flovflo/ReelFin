import Foundation

struct NativePauseStateGate: Equatable {
    private(set) var appliedPausedState: Bool?

    mutating func reset() {
        appliedPausedState = nil
    }

    mutating func shouldApply(_ paused: Bool) -> Bool {
        guard appliedPausedState != paused else { return false }
        appliedPausedState = paused
        return true
    }

    mutating func markApplied(_ paused: Bool) {
        appliedPausedState = paused
    }
}
