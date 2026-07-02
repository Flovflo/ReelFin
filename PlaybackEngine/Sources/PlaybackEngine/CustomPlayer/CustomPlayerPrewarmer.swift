import Foundation
import Shared

/// Everything a play-tap needs, prepared ahead of time.
struct PrewarmedPlayback {
    let resolved: ResolvedOriginalSource
    let session: CacheProxySession
    let localURL: URL
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

    /// Hands the warm pipeline to the engine (once). Also cancels an in-flight warm-up for the
    /// same item so a late-arriving session can never duplicate the engine's own.
    func consume(itemID: String) -> PrewarmedPlayback? {
        guard preparedItemID == itemID else { return nil }
        task?.cancel()
        task = nil
        let result = prepared
        prepared = nil
        preparedItemID = nil
        return result
    }

    /// Frees the warm session (user navigated away without playing). Safe to call repeatedly.
    public func discardIfUnused() {
        task?.cancel()
        task = nil
        prepared?.session.stop()
        prepared = nil
        preparedItemID = nil
    }

#if DEBUG
    /// Test hook: the localhost URL of the prepared session, if warming completed.
    public var debugPreparedLocalURL: URL? { prepared?.localURL }
#endif
}
