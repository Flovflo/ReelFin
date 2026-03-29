import Foundation

public extension PlaybackAssetSelection {
    var isAppleOptimized: Bool {
        if case .directPlay = decision.route {
            return true
        }

        let lane = playbackPlan?.lane ?? decision.playbackPlan?.lane
        return lane == .nativeDirectPlay
    }
}
