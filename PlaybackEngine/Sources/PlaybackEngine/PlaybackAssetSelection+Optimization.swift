import Foundation

public extension PlaybackAssetSelection {
    var isAppleOptimized: Bool {
        if case .directPlay = decision.route {
            return true
        }

        if playbackPlan?.lane == .nativeDirectPlay {
            return true
        }

        return false
    }
}
