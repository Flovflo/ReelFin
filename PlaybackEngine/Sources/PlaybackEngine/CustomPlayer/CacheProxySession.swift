import Foundation
import NativeMediaCore
import Shared

/// One title's local-cache playback lifecycle, as a clean composition over the proven trinity
/// (`OriginDownloader` + `MediaGatewayStore` + `LocalCacheHTTPServer`). This is the heart of the
/// custom player's "keep the original, manage the cache well" design (blueprint §2 / §0-R1):
///
/// - AVPlayer is fed a plain `http://127.0.0.1` URL backed by the disk cache, so **Dolby Vision /
///   HDR render unmodified** (never a custom resource-loader scheme — blueprint N1).
/// - The downloader fills a **deep, dynamic reservoir** ahead of the playhead (depth in SECONDS of
///   the *this-file* bitrate, not a hardcoded byte budget — blueprint §0-R2), so a link dropout
///   shorter than the reservoir is invisible.
/// - `reservoirSecondsAhead(...)` is the cache-depth signal the engine uses to drive the loading
///   indicator and the (dynamic, over-time) keep-original-vs-last-resort decisions.
///
/// Pure composition — no new transport. The only genuinely-new cache logic (range-aware eviction)
/// lives in `CacheBudgetManager`, added separately.
final class CacheProxySession {
    /// Default deep-cache budget per platform. Generous on purpose (the user wants lots of cache),
    /// configurable via `Configuration.cacheBudgetBytes`. iOS 4 GB, tvOS 10 GB.
    public static var defaultCacheBudgetBytes: Int64 {
        #if os(tvOS)
        return 10 * 1_024 * 1_024 * 1_024
        #else
        return 4 * 1_024 * 1_024 * 1_024
        #endif
    }

    struct Configuration {
        /// Reference cushion (seconds) the loading bar measures pre-buffer progress against.
        var targetReservoirSeconds: Double = 180
        /// How far AHEAD of the playhead to keep the original filled, in SECONDS of this file's
        /// bitrate (dynamic-per-file). A deep cushion (≈5 min) gives huge dropout immunity, then the
        /// downloader IDLES — it does NOT race to fill the whole multi-GB disk budget at once, which
        /// was hammering the origin (reset storm) and pressuring memory. The DISK budget (how much
        /// total stays cached, incl. behind the playhead for instant rewind) is the store's own cap.
        var reservoirAheadSeconds: Double = 300
        /// Hard cap on the ahead-fill so a very high-bitrate file can't blow past it (5 min of an
        /// 80 Mbps file would be ~3 GB → clamp to 2 GB of read-ahead).
        var maxAheadBytes: Int64 = 2 * 1_024 * 1_024 * 1_024
        var maxParallelWindows: Int = 6
    }

    private let originURL: URL
    private let headers: [String: String]
    private let key: MediaGatewayCacheKey
    private let store: MediaGatewayStore
    private let overrideMIMEType: String?
    /// The original file's nominal bitrate (bits/s). The byte↔seconds conversion that makes every
    /// reservoir decision dynamic-per-file. Falls back to a conservative default if unknown.
    private let sourceBitrate: Int
    private let config: Configuration

    private var downloader: OriginDownloader?
    private var server: LocalCacheHTTPServer?
    private(set) var localURL: URL?

    /// Bytes per second of the original stream — the conversion factor for reservoir-seconds.
    private var bytesPerSecond: Double { Double(max(1, sourceBitrate)) / 8.0 }

    init(
        originURL: URL,
        headers: [String: String],
        key: MediaGatewayCacheKey,
        store: MediaGatewayStore,
        sourceBitrate: Int?,
        overrideMIMEType: String?,
        configuration: Configuration = Configuration()
    ) {
        self.originURL = originURL
        self.headers = headers
        self.key = key
        self.store = store
        // Unknown bitrate → assume a high-ish 4K-DV-class rate so the reservoir errs DEEP (more
        // cushion) rather than shallow. Better to over-buffer than under-buffer the original.
        self.sourceBitrate = sourceBitrate ?? 30_000_000
        self.overrideMIMEType = overrideMIMEType
        self.config = configuration
    }

    /// Starts the downloader (prime tail/head + forward fill) and the localhost server. Returns the
    /// `http://127.0.0.1` URL to hand to `AVURLAsset` (with `AVURLAssetOverrideMIMETypeKey`).
    func start() throws -> URL {
        let aheadBudget = dynamicAheadBudget()
        let downloader = OriginDownloader(
            remoteURL: originURL,
            headers: headers,
            key: key,
            store: store,
            overrideContentType: overrideMIMEType,
            sessionConfiguration: .ephemeral,
            aheadBudget: aheadBudget,
            maxParallelWindows: config.maxParallelWindows
        )
        let server = LocalCacheHTTPServer(
            store: store,
            downloader: downloader,
            key: key,
            remoteURL: originURL,
            headers: headers,
            overrideMIMEType: overrideMIMEType
        )
        let url = try server.start()
        self.downloader = downloader
        self.server = server
        self.localURL = url
        Task { await downloader.primeStart() }
        AppLog.playback.notice(
            "customplayer.cacheproxy.start — item=\(self.key.itemID.prefix(8), privacy: .public) local=\(url.reelfinCompactLogString, privacy: .public) reservoirTargetSec=\(self.config.targetReservoirSeconds, format: .fixed(precision: 0)) aheadBudgetMB=\(aheadBudget / 1_048_576, privacy: .public) srcMbps=\(self.sourceBitrate / 1_000_000, privacy: .public)"
        )
        return url
    }

    /// How many bytes to keep filled ahead of the playhead: a deep, dynamic-per-file cushion
    /// (`reservoirAheadSeconds` of this bitrate), clamped to `maxAheadBytes` and floored so even a
    /// tiny-bitrate file still reads a sane window ahead. Bounded on purpose so the downloader fills
    /// the cushion then idles instead of racing the whole disk budget (origin reset storm + memory).
    private func dynamicAheadBudget() -> Int64 {
        let bySeconds = Int64(config.reservoirAheadSeconds * bytesPerSecond)
        return min(config.maxAheadBytes, max(64 * 1_024 * 1_024, bySeconds))
    }

    /// Tell the downloader the byte offset playback needs filled forward (drives the read-ahead).
    func setPlayheadOffset(_ offset: Int64) {
        guard let downloader else { return }
        Task { await downloader.setPlayhead(offset) }
    }

    /// Convert a playback time to a byte offset (CBR approximation — adequate for read-ahead aim).
    func byteOffset(forSeconds seconds: Double) -> Int64 {
        Int64(max(0, seconds) * bytesPerSecond)
    }

    /// Seconds of contiguous ORIGINAL already cached ahead of the given playback time — the
    /// cache-depth signal that drives the loading indicator and the keep-original decisions.
    func reservoirSecondsAhead(atSeconds seconds: Double) async -> Double {
        let offset = byteOffset(forSeconds: seconds)
        let end = (try? await store.contiguousEnd(from: offset, key: key)) ?? offset
        return max(0, Double(end - offset) / bytesPerSecond)
    }

    /// The dynamic target the loading bar measures against.
    var targetReservoirSeconds: Double { config.targetReservoirSeconds }

    func stop() {
        server?.stop(reason: "cacheproxy_stop")
        server = nil
        if let downloader { Task { await downloader.stop() } }
        downloader = nil
        localURL = nil
    }
}
