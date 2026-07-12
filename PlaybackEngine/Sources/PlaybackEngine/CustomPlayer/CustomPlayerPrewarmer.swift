import Foundation
import Shared

/// Everything a play-tap needs, prepared ahead of time.
struct PrewarmedPlayback {
    let resolved: ResolvedOriginalSource
    /// Progressive originals own a localhost range cache. Adaptive streams intentionally do not:
    /// HLS playlists/segments must stay in AVPlayer's native adaptive stack.
    let session: CacheProxySession?
    let localURL: URL?
}

/// Perceived-instant start: while the user reads a detail page, this resolves the Jellyfin source,
/// starts the localhost cache session, and primes/fills the startup cushion — so tapping Play just
/// ADOPTS a ready pipeline (`CustomPlaybackEngine` consumes it) instead of paying resolution +
/// prime + cushion at tap time. One title at a time; walking away discards everything (no leaked
/// server, no background fill for a title that will not be played). The disk cost is bounded by
/// the session's own ahead-budget, and everything written stays useful (same cache key as playback).
@MainActor
public final class CustomPlayerPrewarmer {
    private let resolver: CustomPlaybackSourceResolving
    private let store: MediaGatewayStore

    private var task: Task<Void, Never>?
    private var prepared: PrewarmedPlayback?
    private var preparedItemID: String?

    // Focus-dwell resolutions (tvOS): the SOURCE RESOLUTION alone (the PlaybackInfo round trip —
    // the expensive press-time step on a slow link), no cache session per focused card. Bounded
    // and TTL'd; the press consumes its entry and starts the session instantly.
    private var resolvedOnly: [String: (resolved: ResolvedOriginalSource, at: Date)] = [:]
    private var resolveOnlyTask: Task<Void, Never>?
    private var resolveOnlyItemID: String?
    private let resolvedOnlyTTL: TimeInterval = 180
    private let resolvedOnlyCapacity = 8

    public init(resolver: CustomPlaybackSourceResolving, store: MediaGatewayStore) {
        self.resolver = resolver
        self.store = store
    }

    /// Starts (or keeps) warming `itemID`. Idempotent per item; switching items discards the
    /// previous warm session first so two downloaders never fill the same title concurrently.
    public func prewarm(itemID: String, startTimeTicks: Int64? = nil) {
        guard preparedItemID != itemID else { return }
        discardIfUnused()
        preparedItemID = itemID
        task = Task { [weak self] in
            guard let self else { return }
            guard let resolved = try? await self.resolver.resolveOriginal(itemID: itemID, startTimeTicks: startTimeTicks) else { return }
            guard !Task.isCancelled, self.preparedItemID == itemID else { return }
            if resolved.requiresNativePlayback {
                // The native surface owns demux/decode, so there is no progressive cache server to
                // start. Retain the resolution itself so Play can hand off without another request.
                self.prepared = PrewarmedPlayback(resolved: resolved, session: nil, localURL: nil)
                AppLog.playback.notice(
                    "customplayer.prewarm.native_handoff_ready — item=\(itemID.prefix(8), privacy: .public)"
                )
                return
            }
            if resolved.isAdaptiveStream {
                // A Jellyfin HLS URL carries a PlaySessionId. Retaining it while the user reads the
                // detail can make the first segment return HTTP 500. Resolution is deliberately
                // repeated at the actual Play tap; only progressive originals own a full prewarm.
                AppLog.playback.notice(
                    "customplayer.prewarm.adaptive_deferred — item=\(itemID.prefix(8), privacy: .public)"
                )
                return
            }
            let session = CacheProxySession(
                originURL: resolved.originURL, headers: resolved.headers, key: resolved.cacheKey,
                store: self.store, sourceBitrate: resolved.sourceBitrate, overrideMIMEType: resolved.overrideMIMEType)
            guard let localURL = try? await Task.detached(priority: .utility, operation: { try session.start() }).value else { return }
            // Re-check on the MainActor: a consume()/discard() may have raced the detached start.
            guard !Task.isCancelled, self.preparedItemID == itemID, self.prepared == nil else {
                session.stop()
                return
            }
            if let startSeconds = startTimeTicks.map({ Double($0) / 10_000_000 }), startSeconds > 0 {
                session.setPlayheadOffset(session.byteOffset(forSeconds: startSeconds))
            }
            self.prepared = PrewarmedPlayback(resolved: resolved, session: session, localURL: localURL)
            AppLog.playback.notice(
                "customplayer.prewarm.ready — item=\(itemID.prefix(8), privacy: .public) local=\(localURL.reelfinCompactLogString, privacy: .public)"
            )
        }
    }

    /// Hands the warm pipeline to the engine (once). An in-flight warm-up for the SAME item is
    /// ADOPTED (awaited), never cancelled — cancelling it forced the engine to re-resolve from
    /// scratch, paying the full network budget a second time at the worst possible moment. A warm
    /// session for a DIFFERENT item is stopped on the spot: leaving it running kept a second
    /// OriginDownloader filling up to the whole ahead-budget for the wrong title while the pressed
    /// episode fought it for bandwidth.
    func consume(itemID: String) async -> PrewarmedPlayback? {
        guard preparedItemID == itemID else {
            discardIfUnused()
            return nil
        }
        if prepared == nil, let inFlight = task {
            await inFlight.value
        }
        task = nil
        guard preparedItemID == itemID else { return nil }
        let result = prepared
        prepared = nil
        preparedItemID = nil
        return result
    }

    /// Resolve-only warm for a focus dwell: one PlaybackInfo round trip, cached. Idempotent per
    /// item; a newer focus cancels the previous in-flight resolve (one at a time — never a storm).
    /// No-op when the FULL warm already covers the item.
    public func prewarmResolveOnly(itemID: String) {
        guard preparedItemID != itemID else { return }
        if let entry = resolvedOnly[itemID], Date().timeIntervalSince(entry.at) < resolvedOnlyTTL { return }
        guard resolveOnlyItemID != itemID else { return }
        resolveOnlyTask?.cancel()
        resolveOnlyItemID = itemID
        resolveOnlyTask = Task { [weak self] in
            guard let self else { return }
            // nil ticks are suitable only for a from-start focus warm. A Resume press uses a
            // distinct resolver key and adaptive results are rejected below, so its exact ticks
            // can never coalesce with or reuse this speculative request.
            guard let resolved = try? await self.resolver.resolveOriginal(itemID: itemID, startTimeTicks: nil) else {
                if self.resolveOnlyItemID == itemID { self.resolveOnlyItemID = nil }
                return
            }
            guard !Task.isCancelled else { return }
            guard !resolved.isAdaptiveStream else {
                // Adaptive URLs encode the start position and playback session. Resolve them only
                // at Play with the exact resume ticks; a nil-tick focus result is never retained.
                if self.resolveOnlyItemID == itemID { self.resolveOnlyItemID = nil }
                return
            }
            self.resolvedOnly[itemID] = (resolved, Date())
            if self.resolveOnlyItemID == itemID { self.resolveOnlyItemID = nil }
            self.trimResolvedOnly()
            AppLog.playback.notice(
                "customplayer.prewarm.resolved_only — item=\(itemID.prefix(8), privacy: .public)"
            )
            await self.warmOriginContentInfo(resolved: resolved)
        }
    }

    /// One 2-byte range probe on the STREAM URL while the user is still hovering the card:
    /// unwedges the origin path (the first request on this route pays the broken-HTTP/3 timeout —
    /// better now, invisibly, than behind the press spinner) and persists the file's total length,
    /// so the press-time proxy answers AVPlayer's first request with zero origin round trips.
    private func warmOriginContentInfo(resolved: ResolvedOriginalSource) async {
        guard !resolved.isAdaptiveStream, !resolved.requiresNativePlayback else { return }
        if await store.persistedContentLength(key: resolved.cacheKey) != nil { return }
        var request = URLRequest(
            url: PlaybackAuthenticatedRequestURL.forInternalURLSession(resolved.originURL, headers: resolved.headers))
        request.httpMethod = "GET"
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        for (name, value) in resolved.headers { request.setValue(value, forHTTPHeaderField: name) }
        request.timeoutInterval = 12
        guard let (_, response) = try? await MediaOriginTransport.onDemand.data(for: request),
              let http = response as? HTTPURLResponse,
              let total = http.mediaGatewayContentRangeTotal ?? http.mediaGatewayContentLength,
              total > 2 // a 200 whose Content-Length is the 2-byte window would poison the cache
        else { return }
        await store.persistContentLength(total, key: resolved.cacheKey)
        AppLog.playback.notice(
            "customplayer.prewarm.origin_warm — item=\(resolved.cacheKey.itemID.prefix(8), privacy: .public) total=\(total, privacy: .public)"
        )
    }

    /// Hands a focus-dwell resolution to the engine (once). Fresh entries only — a stale direct
    /// URL is worse than a re-resolve.
    func consumeResolvedOnly(itemID: String) -> ResolvedOriginalSource? {
        guard let entry = resolvedOnly.removeValue(forKey: itemID) else { return nil }
        guard Date().timeIntervalSince(entry.at) < resolvedOnlyTTL else { return nil }
        guard !entry.resolved.isAdaptiveStream else { return nil }
        return entry.resolved
    }

    private func trimResolvedOnly() {
        let now = Date()
        resolvedOnly = resolvedOnly.filter { now.timeIntervalSince($0.value.at) < resolvedOnlyTTL }
        while resolvedOnly.count > resolvedOnlyCapacity,
              let oldest = resolvedOnly.min(by: { $0.value.at < $1.value.at }) {
            resolvedOnly.removeValue(forKey: oldest.key)
        }
    }

    /// Frees the warm session (user navigated away without playing). Safe to call repeatedly.
    public func discardIfUnused() {
        task?.cancel()
        task = nil
        prepared?.session?.stop()
        prepared = nil
        preparedItemID = nil
        resolveOnlyTask?.cancel()
        resolveOnlyTask = nil
        resolveOnlyItemID = nil
    }

#if DEBUG
    /// Test hook: the localhost URL of the prepared session, if warming completed.
    public var debugPreparedLocalURL: URL? { prepared?.localURL }
#endif
}
