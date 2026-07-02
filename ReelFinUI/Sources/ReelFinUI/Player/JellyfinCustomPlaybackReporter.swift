import Foundation
import PlaybackEngine
import Shared

/// Bridges the custom engine's narrow progress seam to the Jellyfin API client, so the custom
/// player keeps resume positions / watched state / "Continue watching" in sync exactly like the
/// legacy path. Errors are swallowed on purpose: reporting must never disturb playback.
struct JellyfinCustomPlaybackReporter: CustomPlaybackProgressReporting {
    let apiClient: JellyfinAPIClientProtocol

    func reportProgress(_ update: PlaybackProgressUpdate) async {
        try? await apiClient.reportPlayback(progress: update)
    }

    func reportStopped(_ update: PlaybackProgressUpdate) async {
        try? await apiClient.reportPlaybackStopped(progress: update)
    }
}
