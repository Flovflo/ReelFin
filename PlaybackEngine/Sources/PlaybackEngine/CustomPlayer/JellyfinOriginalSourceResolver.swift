import Foundation
import NativeMediaCore
import Shared

/// Bridges `CustomPlaybackEngine` to the real Jellyfin source selection: resolves the direct-play
/// ORIGINAL (URL, bitrate, DV, headers) via the existing `PlaybackCoordinator`, then packages it as
/// a `ResolvedOriginalSource`. Thin adapter — the engine stays decoupled and offline-testable with
/// a mock; this is the only place that touches the coordinator.
public struct JellyfinOriginalSourceResolver: CustomPlaybackSourceResolving {
    public enum ResolveError: LocalizedError {
        case notDirectPlayable
        public var errorDescription: String? {
            switch self {
            case .notDirectPlayable:
                return "This title is not directly playable as an original; an adaptive lane is required."
            }
        }
    }

    private let coordinator: PlaybackCoordinator
    /// Audio/subtitle signatures for the cache key (so a different track selection caches separately).
    private let audioSignature: String
    private let subtitleSignature: String

    public init(coordinator: PlaybackCoordinator, audioSignature: String = "default", subtitleSignature: String = "default") {
        self.coordinator = coordinator
        self.audioSignature = audioSignature
        self.subtitleSignature = subtitleSignature
    }

    public func resolveOriginal(itemID: String, startTimeTicks: Int64?) async throws -> ResolvedOriginalSource {
        // Pass a non-nil fallback reason (not the post-start-stall sentinel) so the coordinator's
        // legacy native-route self-block is bypassed and it resolves the direct-play original. That
        // guard is removed entirely when the legacy engine is stripped (blueprint Phase 7).
        let selection = try await coordinator.resolvePlayback(
            itemID: itemID,
            startTimeTicks: startTimeTicks,
            allowDirectRoutes: true,
            nativeEngineFallbackReason: "custom_player_engine"
        )
        guard case .directPlay = selection.decision.route else {
            throw ResolveError.notDirectPlayable
        }

        let assetURL = selection.assetURL
        let overrideMIMEType = Self.overrideMIMEType(for: assetURL, container: selection.source.container)
        let key = MediaGatewayCacheKey(
            scope: "directplay-original",
            userID: nil,
            serverID: assetURL.host,
            itemID: selection.source.itemID,
            sourceID: selection.source.id,
            routeURL: assetURL,
            routeHeaders: selection.headers,
            audioSignature: audioSignature,
            subtitleSignature: subtitleSignature,
            resumeSeconds: nil
        )
        return ResolvedOriginalSource(
            originURL: assetURL,
            headers: selection.headers,
            sourceBitrate: selection.source.bitrate,
            overrideMIMEType: overrideMIMEType,
            cacheKey: key,
            isDolbyVision: selection.source.isLikelyHDRorDV
        )
    }

    /// Extensionless direct-play origins need a MIME hint so AVPlayer enters the right parser (and,
    /// crucially, keeps DV + the AC3 audio track). Mirror the PROVEN legacy direct-play behavior,
    /// which used `video/mp4` for this content — `container` here is the device-profile container
    /// LIST (e.g. "mov,mp4,m4a,…"), not the real file container, so do NOT branch on it to quicktime
    /// (that regressed audio after ~10s on device).
    static func overrideMIMEType(for url: URL, container: String?) -> String? {
        guard url.pathExtension.isEmpty else { return nil }
        return "video/mp4"
    }
}
