import Foundation

struct NativeAudioStartupWatchdog: Equatable {
    private var firstWaitTime: TimeInterval?

    mutating func reset() {
        firstWaitTime = nil
    }

    mutating func shouldDegradeAudio(
        now: TimeInterval,
        snapshot: NativePlaybackBufferSnapshot,
        decision: NativePlaybackBufferDecision,
        needsAudio: Bool,
        maximumWaitSeconds: TimeInterval
    ) -> Bool {
        guard needsAudio, !decision.canStart else {
            reset()
            return false
        }
        guard decision.videoAheadSeconds >= decision.requiredVideoAheadSeconds,
              snapshot.videoPacketCount > 0 else {
            firstWaitTime = nil
            return false
        }
        if firstWaitTime == nil {
            firstWaitTime = now
        }
        guard let firstWaitTime else { return false }
        return now - firstWaitTime >= maximumWaitSeconds
    }
}
