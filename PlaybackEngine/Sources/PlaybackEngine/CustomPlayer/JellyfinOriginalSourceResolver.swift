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
            nativeEngineFallbackReason: "custom_player_engine",
            // Prefer a progressive MP4/MOV twin over an MKV: AVKit reads MP4 linearly so it stays
            // inside the contiguous localhost cache (no index-seek cache-misses → no cuts), keeping
            // the same HEVC/Dolby-Vision bitstream. Falls back to whatever exists (e.g. MKV-only).
            preferredContainers: ["mp4", "m4v", "mov"]
        )
        guard case .directPlay = selection.decision.route else {
            throw ResolveError.notDirectPlayable
        }

        let assetURL = selection.assetURL
        let overrideMIMEType = Self.overrideMIMEType(for: assetURL, source: selection.source)
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

    /// Extensionless direct-play origins need a MIME hint so AVKit picks the RIGHT demuxer — getting
    /// this wrong on a localhost source makes AVKit grab only one track (device: video/mp4 → audio
    /// but no image; video/quicktime → image but no audio on an MKV). The legacy gets away with
    /// video/mp4 because AVKit sniffs the real bytes off the origin; through the localhost cache it
    /// needs the CORRECT type. Use the real file extension first (`source.filePath`), then the
    /// container — and crucially recognize **mkv → video/x-matroska** (the legacy MIME table didn't).
    static func overrideMIMEType(for url: URL, source: MediaSource) -> String? {
        guard url.pathExtension.isEmpty else { return nil }
        if let filePath = source.filePath {
            let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
            if let mime = mime(forExtension: ext) { return mime }
        }
        let tokens = (source.container ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if tokens.contains("mkv") || tokens.contains("matroska") { return "video/x-matroska" }
        if tokens.contains("mp4") || tokens.contains("m4v") { return "video/mp4" }
        if tokens.contains("mov") || tokens.contains("qt") { return "video/quicktime" }
        return "video/mp4"
    }

    private static func mime(forExtension ext: String) -> String? {
        switch ext {
        case "mkv", "matroska": return "video/x-matroska"
        case "mp4", "m4v": return "video/mp4"
        case "mov", "qt": return "video/quicktime"
        case "webm": return "video/webm"
        default: return nil
        }
    }
}

extension JellyfinOriginalSourceResolver: CustomPlaybackAdaptiveFallbackResolving {
    /// Resolves the clean SDR fallback: Jellyfin H.264 HLS transcode STARTING at `startSeconds`
    /// (server tone-maps HDR→SDR — never the dark HEVC stream-copy path). Scoped to this call
    /// only: `allowDirectRoutes=false` flips transcoding on for THIS resolution, startup routing
    /// is untouched (the global-transcode black-screen lesson). Returns nil when the server offers
    /// no transcode — the engine then stays on the original with the honest loading bar.
    public func resolveAdaptiveFallback(itemID: String, startSeconds: Double) async -> URL? {
        let ticks = Int64(max(0, startSeconds) * 10_000_000)
        guard let selection = try? await coordinator.resolvePlayback(
            itemID: itemID,
            transcodeProfile: .forceH264Transcode,
            startTimeTicks: ticks > 0 ? ticks : nil,
            allowDirectRoutes: false,
            nativeEngineFallbackReason: "custom_player_sdr_fallback"
        ) else { return nil }
        switch selection.decision.route {
        case .transcode, .remux:
            return selection.assetURL
        case .directPlay, .nativeBridge:
            return nil // defense in depth: the fallback lane never plays a direct route
        }
    }
}
