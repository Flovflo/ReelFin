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

    /// Process-wide resolution memo. A resolve can serially burn several PlaybackInfo POSTs
    /// (initial + dedicated-profile + balanced fallback), each with a full network timeout — on a
    /// degraded link that is MINUTES behind the play-press spinner. Every resolver instance (focus
    /// warm, detail prewarm, the engine at press time) shares this: any earlier resolution makes
    /// the press instant, and concurrent resolves for the same title coalesce into one.
    private final class ResolutionMemo: @unchecked Sendable {
        static let shared = ResolutionMemo()
        private let lock = NSLock()
        private var cached: [String: (resolved: ResolvedOriginalSource, at: Date)] = [:]
        private var inFlight: [String: Task<ResolvedOriginalSource, Error>] = [:]
        private let ttl: TimeInterval = 180

        func hit(_ key: String) -> ResolvedOriginalSource? {
            lock.lock(); defer { lock.unlock() }
            guard let entry = cached[key] else { return nil }
            guard Date().timeIntervalSince(entry.at) < ttl else {
                cached[key] = nil
                return nil
            }
            return entry.resolved
        }

        func task(_ key: String) -> Task<ResolvedOriginalSource, Error>? {
            lock.lock(); defer { lock.unlock() }
            return inFlight[key]
        }

        func register(_ task: Task<ResolvedOriginalSource, Error>, for key: String) {
            lock.lock(); defer { lock.unlock() }
            inFlight[key] = task
        }

        func finish(_ key: String, result: ResolvedOriginalSource?) {
            lock.lock(); defer { lock.unlock() }
            inFlight[key] = nil
            // Adaptive streams embed the start position in their URL — never memoize those.
            if let result, !result.isAdaptiveStream {
                cached[key] = (result, Date())
            }
            if cached.count > 16 {
                let cutoff = Date().addingTimeInterval(-ttl)
                cached = cached.filter { $0.value.at > cutoff }
            }
        }
    }

    private var memoKey: (String) -> String {
        { itemID in "\(itemID)|\(self.audioSignature)|\(self.subtitleSignature)" }
    }

    public func resolveOriginal(itemID: String, startTimeTicks: Int64?) async throws -> ResolvedOriginalSource {
        let key = memoKey(itemID)
        if let hit = ResolutionMemo.shared.hit(key) {
            AppLog.playback.notice("customplayer.resolve.memo_hit — item=\(itemID.prefix(8), privacy: .public)")
            return hit
        }
        if let inFlight = ResolutionMemo.shared.task(key) {
            AppLog.playback.notice("customplayer.resolve.memo_join — item=\(itemID.prefix(8), privacy: .public)")
            return try await inFlight.value
        }
        let task = Task { try await performResolveOriginal(itemID: itemID, startTimeTicks: startTimeTicks) }
        ResolutionMemo.shared.register(task, for: key)
        do {
            let resolved = try await task.value
            ResolutionMemo.shared.finish(key, result: resolved)
            return resolved
        } catch {
            ResolutionMemo.shared.finish(key, result: nil)
            throw error
        }
    }

    private func performResolveOriginal(itemID: String, startTimeTicks: Int64?) async throws -> ResolvedOriginalSource {
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
        if Self.requiresNativeOriginalPlayback(for: selection.source) {
            return resolvedNativeHandoff(selection: selection)
        }
        switch selection.decision.route {
        case .directPlay:
            break
        case .remux, .transcode:
            // Keep Jellyfin's FIRST selection. It may be a lossless DirectStream/video-copy remux
            // (MKV → Apple-compatible HLS). Re-fetching with direct routes disabled destroyed that
            // route and silently produced H.264 instead — exactly the "Qualité adaptée" regression.
            return resolvedAdaptive(selection: selection)
        case .nativeBridge:
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
            preservesOriginalVideo: true,
            isAdaptiveStream: false,
            externalSubtitles: Self.externalSubtitleTracks(for: selection.source, assetURL: assetURL)
        )
    }

    private func resolvedAdaptive(selection: PlaybackAssetSelection) -> ResolvedOriginalSource {
        let assetURL = selection.assetURL
        return ResolvedOriginalSource(
            originURL: assetURL,
            headers: selection.headers,
            sourceBitrate: selection.source.bitrate,
            overrideMIMEType: nil,
            cacheKey: MediaGatewayCacheKey(
                scope: selection.routeGuarantees.preservesOriginalVideo ? "adaptive-video-copy" : "adaptive",
                userID: nil,
                serverID: assetURL.host,
                itemID: selection.source.itemID,
                sourceID: selection.source.id,
                routeURL: assetURL,
                routeHeaders: selection.headers,
                audioSignature: audioSignature,
                subtitleSignature: subtitleSignature,
                resumeSeconds: nil
            ),
            isDolbyVision: selection.source.isLikelyHDRorDV && selection.routeGuarantees.preservesOriginalVideo,
            preservesOriginalVideo: selection.routeGuarantees.preservesOriginalVideo,
            isAdaptiveStream: true,
            externalSubtitles: Self.externalSubtitleTracks(for: selection.source, assetURL: assetURL)
        )
    }

    private func resolvedNativeHandoff(selection: PlaybackAssetSelection) -> ResolvedOriginalSource {
        let assetURL = selection.assetURL
        return ResolvedOriginalSource(
            originURL: assetURL,
            headers: selection.headers,
            sourceBitrate: selection.source.bitrate,
            overrideMIMEType: nil,
            cacheKey: MediaGatewayCacheKey(
                scope: "native-original-handoff",
                userID: nil,
                serverID: assetURL.host,
                itemID: selection.source.itemID,
                sourceID: selection.source.id,
                routeURL: assetURL,
                routeHeaders: selection.headers,
                audioSignature: audioSignature,
                subtitleSignature: subtitleSignature,
                resumeSeconds: nil
            ),
            isDolbyVision: selection.source.isLikelyHDRorDV,
            preservesOriginalVideo: true,
            isAdaptiveStream: false,
            requiresNativePlayback: true,
            externalSubtitles: Self.externalSubtitleTracks(for: selection.source, assetURL: assetURL)
        )
    }

    /// The custom AVPlayer path keeps Apple-native files on its fast progressive cache. A lone
    /// Matroska HEVC/H.264 source instead needs ReelFin's packet demuxer: raw MKV is not a reliable
    /// AVPlayer input, and Jellyfin's fMP4 remux has produced audio-only assets in real tvOS tests.
    static func requiresNativeOriginalPlayback(for source: MediaSource) -> Bool {
        let containers = PlaybackCoordinator.sourceContainerTokens(source)
        guard containers.contains("mkv") || containers.contains("matroska") else { return false }
        switch source.normalizedVideoCodec {
        case "hevc", "h265", "hvc1", "hev1", "h264", "avc1":
            return true
        default:
            return false
        }
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
            return resolvedAdaptive(selection: selection)
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
