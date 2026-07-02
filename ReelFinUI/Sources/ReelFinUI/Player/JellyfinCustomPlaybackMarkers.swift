import Foundation
import PlaybackEngine
import Shared

/// Jellyfin adapter for the engine's markers seam: fetches intro/credits media segments, sorted
/// and validity-filtered exactly like the legacy path did. Errors degrade to "no segments" —
/// markers must never disturb playback.
struct JellyfinCustomPlaybackMarkers: CustomPlaybackMarkersProviding {
    let apiClient: JellyfinAPIClientProtocol

    func mediaSegments(itemID: String) async -> [MediaSegment] {
        let segments = (try? await apiClient.fetchMediaSegments(itemID: itemID)) ?? []
        return segments
            .filter(\.isValid)
            .sorted { lhs, rhs in
                if lhs.startTicks != rhs.startTicks {
                    return lhs.startTicks < rhs.startTicks
                }
                return lhs.type.rawValue < rhs.type.rawValue
            }
    }
}
