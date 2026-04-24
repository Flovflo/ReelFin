import Foundation

struct NativeAudioStarvationGate: Equatable {
    var minimumStarvationDuration: TimeInterval
    private(set) var starvationStartTime: TimeInterval?
    private(set) var starvationTicks = 0

    init(minimumStarvationDuration: TimeInterval) {
        self.minimumStarvationDuration = minimumStarvationDuration
    }

    mutating func reset() {
        starvationStartTime = nil
        starvationTicks = 0
    }

    mutating func update(isStarved: Bool, now: TimeInterval) -> NativeAudioStarvationDecision {
        guard isStarved else {
            reset()
            return NativeAudioStarvationDecision(ticks: 0, elapsedSeconds: 0, shouldRebuffer: false)
        }

        starvationTicks += 1
        let started = starvationStartTime ?? now
        starvationStartTime = started
        let elapsed = max(0, now - started)
        return NativeAudioStarvationDecision(
            ticks: starvationTicks,
            elapsedSeconds: elapsed,
            shouldRebuffer: elapsed >= minimumStarvationDuration
        )
    }
}

struct NativeAudioStarvationDecision: Equatable {
    var ticks: Int
    var elapsedSeconds: TimeInterval
    var shouldRebuffer: Bool
}
