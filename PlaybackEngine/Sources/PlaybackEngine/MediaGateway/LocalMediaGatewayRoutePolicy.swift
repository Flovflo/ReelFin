import Foundation
import Shared

public enum LocalMediaGatewayRoutePolicy {
    public static func shouldUseGateway(
        route: PlaybackRoute,
        source: MediaSource?,
        mediaCacheMode: MediaCacheMode,
        isTVOS: Bool,
        resumeSeconds: Double?,
        hasCachedBytes: Bool,
        cachedBytes: Int64 = 0
    ) -> Bool {
        // The local cache gateway is DISABLED on the playback path. Direct play — first play OR
        // resume, cached OR uncached, iOS or tvOS — streams straight from the origin via AVPlayer.
        //
        // Measured against the live origin (jellyfin.taffin.ovh `/Videos/{id}/stream`): ~100 Mbps
        // sustained with ~120 ms TTFB and clean `206 Partial Content` at BOTH offset 0 and a deep
        // ~3.3 GB resume offset — roughly 4x the 26 Mbps a high-bitrate DV/4K original needs.
        // AVPlayer pointed straight at it never starves.
        //
        // Interposing the local proxy, by contrast, churns and stalls: AVPlayer reconnects per
        // range (the gateway answers `Connection: close`), and per window the gateway opens a
        // fresh upstream `URLSession` — a new TLS handshake to the remote origin — and cancels the
        // in-flight window when AVPlayer disconnects. On a large original this starved the buffer
        // and produced `MEDIA_PLAYBACK_STALL` on BOTH first play and resume, even with 700 MB+
        // already cached (device logs: a flood of `gateway.stream_failed_after_headers`). Cached
        // bytes didn't help because every uncached gap still triggered the churn.
        //
        // The gateway type stays as dormant infrastructure for a future churn-free read-ahead
        // cache (single persistent upstream session + windows that finish caching past an AVPlayer
        // disconnect). A genuine origin range failure is handled by recovery → transcode profiles
        // (never a permanent black screen).
        _ = (route, source, mediaCacheMode, isTVOS, resumeSeconds, hasCachedBytes, cachedBytes)
        return false
    }
}

/// Gate for the cache-loader playback path (`CacheResourceLoaderDelegate` + `OriginDownloader`):
/// AVPlayer reads raw original bytes from the app `MediaGatewayStore` while a single keep-alive
/// downloader fills ahead and resumes through connection drops. No HLS/transcode, so Dolby Vision
/// and full quality are preserved, and a real `-1005` reset is absorbed without a cut
/// (proven in `PlaybackDropResilienceTests`).
///
/// This is the churn-free read-ahead cache the dormant proxy note in `LocalMediaGatewayRoutePolicy`
/// anticipated — but on the resource-loader path, not the NWListener proxy.
public enum CacheLoaderRoutePolicy {
    /// Master rollout switch. ON: AVPlayer reads from the app cache while a PARALLEL multi-connection
    /// downloader fills a deep buffer ahead of the playhead — exploiting bandwidth bursts to ride out
    /// the dropouts (the Infuse approach). Keeps Dolby Vision (raw original, no transcode). Single-
    /// connection couldn't keep up (28-30 Mbps vs AVPlayer's 232); parallel range requests close the
    /// gap. Falls back to recovery on a genuine sustained outage.
    /// OFF — CRITICAL: the cache loader BREAKS Dolby Vision rendering on device (BLACK screen),
    /// even though it serves H.264 fine (CacheLoaderLiveIntegrationTests passed because the sim
    /// can't decode DV). AVPlayer renders DV through a direct AVURLAsset but NOT through the custom
    /// reelfin-cache resource-loader scheme (likely the overrideMIMEType/scheme loses the DV
    /// configuration). The user's content is DV → the cache loader is not viable for them. The
    /// never-cut path for DV is direct-play + adaptive-HLS fallback, not this.
    public static let isEnabled = false

    public static func shouldUseCacheLoader(
        route: PlaybackRoute,
        source: MediaSource?,
        assetURL: URL,
        isTVOS: Bool,
        hasStore: Bool
    ) -> Bool {
        _ = source
        guard isEnabled else { return false }
        guard hasStore else { return false }
        // iOS first; tvOS enabled after on-device validation.
        guard !isTVOS else { return false }
        // Only the direct-play raw-original route — never remux/transcode/HLS.
        guard case .directPlay = route else { return false }
        // Range-capable HTTP origin (the loader serves byte ranges from the store the downloader
        // fills via closed-range GETs).
        guard let scheme = assetURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        // TODO(rollout): also honor `mediaCacheMode != .off` and WiFi/unconstrained-only here once
        // the value is threaded synchronously to the asset-construction seam.
        return true
    }
}

/// Gate for the localhost HTTP cache proxy (`LocalCacheHTTPServer` + `OriginDownloader` +
/// `MediaGatewayStore`): AVPlayer reads raw original bytes from `http://127.0.0.1:port` while the
/// parallel downloader fills a deep buffer ahead of the playhead. Same proven never-stall cache as
/// the resource-loader cache loader, but delivered over a plain localhost HTTP URL so Dolby Vision
/// renders correctly (the custom `reelfin-cache://` scheme black-screened DV; a localhost HTTP URL
/// is indistinguishable from the origin to AVFoundation). This is the Infuse-class never-cut path:
/// AVPlayer's buffer is fed from the local cache, so origin dropouts can't drain it.
public enum LocalCacheProxyRoutePolicy {
    /// Master switch. ON: direct play is served through the localhost cache proxy (deep parallel
    /// read-ahead, DV preserved). The adaptive HLS fallback remains the backstop for a genuinely
    /// sustained origin outage (cache fully drained → AVPlayer stall → recovery → watchable SDR).
    /// v2 (2026-06-27): added serve-path ON-DEMAND fetch — a cache-missed range (AVPlayer's first
    /// read / a seek) is fetched directly at direct-play latency while the background downloader
    /// builds the deep cushion ahead. Fixes the v1 device regression (deep-resume blocked on the
    /// windowed downloader → TTFF 17.5s). Proven in PlaybackDropResilienceTests: deep-resume first
    /// frame 3.8s (non-blocking prime), zero stalls + byte-exact through a real origin reset.
    public static let isEnabled = true

    public static func shouldUseProxy(
        route: PlaybackRoute,
        source: MediaSource?,
        assetURL: URL,
        isTVOS: Bool,
        hasStore: Bool
    ) -> Bool {
        _ = source
        guard isEnabled else { return false }
        guard hasStore else { return false }
        // iOS first; tvOS enabled after on-device validation.
        guard !isTVOS else { return false }
        // Only the direct-play raw-original route — never remux/transcode/HLS.
        guard case .directPlay = route else { return false }
        // Range-capable HTTP origin (the proxy serves byte ranges from the store the downloader
        // fills via closed-range GETs).
        guard let scheme = assetURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return true
    }
}

/// Adaptive in-stream fallback: when direct play (max quality, e.g. Dolby Vision) cannot be
/// sustained on the current connection, the player drops to a Jellyfin adaptive HLS/transcode
/// stream so it NEVER freezes, instead of the deliberate "DV-or-nothing" lock that froze playback.
/// This is the Infuse-style behavior the user asked for: max quality when bandwidth allows,
/// graceful quality drop (never a cut) when it doesn't.
public enum AdaptiveFallbackPolicy {
    /// Master switch for adaptive transcode fallback. ON: a sustained direct-play stall escalates
    /// to a sustainable-bitrate HLS transcode (loses DV temporarily, never freezes). OFF restores
    /// the strict native-engine "direct-only" lock.
    /// ON — the never-cut path for DV. Startup is byte-identical to baseline (direct-play DV via a
    /// normal AVURLAsset → renders, unlike the cache loader which black-screened DV). On a sustained
    /// post-start stall (the "ça coupe" case the recovery currently can't escape), it escalates to a
    /// sustainable HLS transcode via a NORMAL AVURLAsset (renders, never freezes). Recovery-scoped:
    /// only affects the stall path, never the initial route. Test updated to match.
    public static let isEnabled = true
}
