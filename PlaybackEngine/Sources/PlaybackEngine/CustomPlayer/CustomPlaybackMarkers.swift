import Foundation
import Shared

/// Narrow seam for playback markers (intro/credits segments) so the engine can surface skip
/// suggestions without depending on the whole API client. The app provides a Jellyfin adapter;
/// tests provide fixtures.
public protocol CustomPlaybackMarkersProviding: Sendable {
    func mediaSegments(itemID: String) async -> [MediaSegment]
}
