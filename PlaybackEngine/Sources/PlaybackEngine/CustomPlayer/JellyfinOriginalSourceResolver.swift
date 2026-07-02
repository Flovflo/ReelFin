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
            // Not playable as a raw original (container/codec AVFoundation can't open) — hand the
            // engine the server's adaptive stream instead of failing. Best server-chosen quality,
            // resolved lazily and scoped to this call.
            if let adaptive = await resolveAdaptiveSelection(itemID: itemID, startTimeTicks: startTimeTicks) {
                return adaptive
            }
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
            isDolbyVision: selection.source.isLikelyHDRorDV,
            isAdaptiveStream: false,
            externalSubtitles: Self.externalSubtitleTracks(for: selection.source, assetURL: assetURL)
        )
    }

    /// Text sidecar subtitle tracks (SRT/VTT) of the resolved source, with Jellyfin delivery URLs
    /// derived from the asset URL's server + api_key. Image formats (PGS) can't be text-rendered.
    static func externalSubtitleTracks(for source: MediaSource, assetURL: URL) -> [ExternalSubtitleTrack] {
        let textCodecs: Set<String> = ["srt", "subrip", "vtt", "webvtt"]
        guard var components = URLComponents(url: assetURL, resolvingAgainstBaseURL: false) else { return [] }
        let apiKey = components.queryItems?.first { $0.name.lowercased() == "api_key" }?.value
        return source.subtitleTracks.compactMap { track in
            guard let codec = track.codec?.lowercased(), textCodecs.contains(codec) else { return nil }
            components.path = "/Videos/\(source.itemID)/\(source.id)/Subtitles/\(track.index)/0/Stream.srt"
            components.queryItems = apiKey.map { [URLQueryItem(name: "api_key", value: $0)] }
            guard let url = components.url else { return nil }
            let label = track.title.isEmpty ? (track.language ?? "Subtitle \(track.index)") : track.title
            return ExternalSubtitleTrack(id: track.id, label: label, url: url)
        }
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
        // The composite "mov,mp4,m4a,3gp,3g2,mj2" is ffmpeg's shared label for the WHOLE QuickTime
        // family — real .mp4 files report it too (live probe 2026-07-02: '…FW.mp4' carries exactly
        // that string). It cannot discriminate mov vs mp4; only the file extension can (handled
        // above via `source.filePath`). mp4 stays the composite default; "mov" alone maps QuickTime.
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

extension JellyfinOriginalSourceResolver {
    /// Adaptive selection for a source that cannot direct-play at all: the server's default
    /// transcode/remux (its best quality choice for the client), packaged for the engine's
    /// adaptive-only lane. Returns nil when the server offers no stream.
    func resolveAdaptiveSelection(itemID: String, startTimeTicks: Int64?) async -> ResolvedOriginalSource? {
        guard let selection = try? await coordinator.resolvePlayback(
            itemID: itemID,
            startTimeTicks: startTimeTicks,
            allowDirectRoutes: false,
            nativeEngineFallbackReason: "custom_player_adaptive_lane"
        ) else { return nil }
        switch selection.decision.route {
        case .transcode, .remux:
            return ResolvedOriginalSource(
                originURL: selection.assetURL,
                headers: selection.headers,
                sourceBitrate: selection.source.bitrate,
                overrideMIMEType: nil,
                cacheKey: MediaGatewayCacheKey(
                    scope: "adaptive",
                    userID: nil,
                    serverID: selection.assetURL.host,
                    itemID: selection.source.itemID,
                    sourceID: selection.source.id,
                    routeURL: selection.assetURL,
                    routeHeaders: selection.headers,
                    audioSignature: audioSignature,
                    subtitleSignature: subtitleSignature,
                    resumeSeconds: nil
                ),
                isDolbyVision: false,
                isAdaptiveStream: true
            )
        case .directPlay, .nativeBridge:
            return nil
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
