import Foundation
import NativeMediaCore
import Shared

/// The single component that touches the origin server during a cache-loader playback session.
///
/// Design (the four non-negotiables for never-cut):
/// 1. **Owns its lifetime, not a serve request.** AVPlayer disconnecting a resource request never
///    cancels a download; only `stop()` does. This kills every connection-churn path.
/// 2. **One persistent keep-alive session** (`StreamingRangeWriter`, `httpMaximumConnectionsPerHost = 2`,
///    default QoS — not `.background`) reused across all windows.
/// 3. **Closed ranges only** (`bytes={off}-{off+window-1}`) so each window is fully read and the
///    connection returns to the pool — never the open-ended `cancel()`-at-maxLength churn.
/// 4. **Commit-as-you-go + resumable retry.** Each ≥256 KB sub-block is written to the store as it
///    arrives; a transient drop resumes from the store's contiguous end — no byte re-fetched,
///    retried indefinitely while playback is live (the loader's liveness deadline is the floor).
///
/// The store is the SINGLE coverage authority: the downloader writes; serve loops wake off the
/// store's `coverageEvents`. The downloader keeps a bounded lookahead ahead of the playhead and
/// re-anchors to follow seeks.
actor OriginDownloader {
    private let remoteURL: URL
    private let headers: [String: String]
    private let key: MediaGatewayCacheKey
    private let store: MediaGatewayStore
    private let overrideContentType: String?
    private let probeConfiguration: URLSessionConfiguration
    private let streamer: StreamingRangeWriter

    private let windowLength: Int64
    // Deep cushion ahead of the REAL playhead so a multi-second drop is absorbed from cache.
    // 512 MiB ≈ 2.5 min at 26 Mbps. Injectable so tests can force a small budget (reproducing a
    // file much larger than the lookahead, like the 11.7 GB device original).
    private let aheadBudget: Int64
    private let reanchorDistance: Int64 = 2 * 1_024 * 1_024
    // How many windows to fetch concurrently. Parallel range requests saturate a bursty/throttled
    // origin so the buffer fills fast during bursts (Infuse-style) and survives the dropouts.
    private let maxParallelWindows: Int
    private let headLength: Int64
    private let tailLength: Int64
    private let minSubBlock = 256 * 1_024

    private var totalLength: Int64?
    private var resolvedContentType: String?
    private var contentInfoTask: Task<(Int64?, String?), Never>?
    private let contentInfoMaxAttempts = 5
    /// The byte offset playback actually needs filled forward — the MAX offset across AVPlayer's
    /// active requests (the loader computes the max). The downloader always fills from the first
    /// gap at/after this. Following the max (not a per-request anchor) is what stops the moov/head
    /// metadata request from yanking the fill back to the start of the file on a resume/seek.
    private var playhead: Int64 = 0
    private var fillTask: Task<Void, Never>?
    private var didPrime = false

    init(
        remoteURL: URL,
        headers: [String: String],
        key: MediaGatewayCacheKey,
        store: MediaGatewayStore,
        overrideContentType: String?,
        sessionConfiguration: URLSessionConfiguration,
        windowLength: Int64 = 8 * 1_024 * 1_024,
        aheadBudget: Int64 = 512 * 1_024 * 1_024,
        maxParallelWindows: Int = 6,
        headLength: Int64 = 8 * 1_024 * 1_024,
        tailLength: Int64 = 4 * 1_024 * 1_024
    ) {
        self.remoteURL = remoteURL
        self.headers = headers
        self.key = key
        self.store = store
        self.overrideContentType = overrideContentType
        self.windowLength = max(1, windowLength)
        self.aheadBudget = max(windowLength, aheadBudget)
        self.maxParallelWindows = max(1, maxParallelWindows)
        self.headLength = max(1, headLength)
        self.tailLength = max(1, tailLength)
        let probeConfig = (sessionConfiguration.copy() as? URLSessionConfiguration) ?? .ephemeral
        // The FIRST range request to an idle origin item can cold-start for ~15s (server/CF warm
        // up the file). Give the probe room to ride that out instead of timing out and failing.
        probeConfig.timeoutIntervalForRequest = 25
        probeConfig.timeoutIntervalForResource = 120
        self.probeConfiguration = probeConfig
        self.streamer = StreamingRangeWriter(configuration: sessionConfiguration)
    }

    // MARK: - Public API (called by the cache resource loader)

    /// One-shot probe for total length + content type. Cached after the first call. The content
    /// type honours the extensionless-direct-play override decision so a DV original doesn't
    /// regress the `AVPlayerItem` to `.unknown`.
    func contentInfo() async -> (length: Int64?, contentType: String?) {
        if let totalLength {
            return (totalLength, resolvedContentType)
        }
        // OFFLINE-FIRST: reuse the total length persisted from a prior play, so a previously-cached
        // title starts straight from disk with NO origin probe. This is what lets the deep cache be
        // used when the origin is unreachable (the user's "I have 800s cached, why can't I use it?").
        if let persisted = await store.persistedContentLength(key: key) {
            totalLength = persisted
            if resolvedContentType == nil { resolvedContentType = overrideContentType }
            return (persisted, resolvedContentType)
        }
        // Coalesce concurrent callers (primeStart + the serve loop both ask) onto one probe so a
        // cold item is warmed exactly once.
        if let contentInfoTask {
            return await contentInfoTask.value
        }
        let task = Task<(Int64?, String?), Never> { [weak self] in
            guard let self else { return (nil, nil) }
            return await self.resolveContentInfo()
        }
        contentInfoTask = task
        let result = await task.value
        // On failure, drop the cached task so a later request can retry from scratch.
        if result.0 == nil { contentInfoTask = nil }
        return result
    }

    /// Probes `bytes=0-1` for total length + content type, retrying through the cold-start window
    /// and transient drops. The 25s per-attempt timeout (set on `probeConfiguration`) absorbs the
    /// ~15s first-request warm-up; a few attempts cover transient `-1005`/`-1001`.
    private func resolveContentInfo() async -> (Int64?, String?) {
        var attempt = 0
        while attempt < contentInfoMaxAttempts, !Task.isCancelled {
            attempt += 1
            var request = URLRequest(url: PlaybackAuthenticatedRequestURL.forInternalURLSession(remoteURL, headers: headers))
            request.httpMethod = "GET"
            request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            do {
                let (_, http) = try await HTTPChunkedRangeReader.collect(
                    request: request,
                    configuration: (probeConfiguration.copy() as? URLSessionConfiguration) ?? .ephemeral,
                    maxLength: 2
                )
                if let total = http.mediaGatewayContentRangeTotal ?? http.mediaGatewayContentLength {
                    totalLength = total
                    resolvedContentType = overrideContentType ?? http.value(forHTTPHeaderField: "Content-Type")
                    // Persist so the next play (even with the origin DOWN) starts from the disk cache.
                    await store.persistContentLength(total, key: key)
                    AppLog.playback.notice(
                        "playback.cacheloader.contentinfo — item=\(self.key.itemID.prefix(8), privacy: .public) attempt=\(attempt, privacy: .public) total=\(total, privacy: .public) type=\(self.resolvedContentType ?? "-", privacy: .public)"
                    )
                    return (total, resolvedContentType)
                }
                AppLog.playback.warning(
                    "playback.cacheloader.contentinfo.nolength — item=\(self.key.itemID.prefix(8), privacy: .public) attempt=\(attempt, privacy: .public) status=\(http.statusCode, privacy: .public)"
                )
            } catch {
                AppLog.playback.warning(
                    "playback.cacheloader.contentinfo.retry — item=\(self.key.itemID.prefix(8), privacy: .public) attempt=\(attempt, privacy: .public) reason=\(error.localizedDescription, privacy: .public)"
                )
            }
            if attempt < contentInfoMaxAttempts {
                try? await Task.sleep(nanoseconds: 500_000_000 * UInt64(attempt))
            }
        }
        return (nil, overrideContentType)
    }

    /// Warm the cache for a fast first frame: probe, then fetch the tail (moov is often at EOF in
    /// non-faststart MP4) and the head, strictly ordered, before the forward fill loop takes over.
    func primeStart() async {
        guard !didPrime else { return }
        didPrime = true
        _ = await contentInfo()
        if let total = totalLength, total > tailLength {
            try? await downloadWindow(from: total - tailLength, to: total)
        }
        let headEnd = totalLength.map { min(headLength, $0) } ?? headLength
        try? await downloadWindow(from: 0, to: headEnd)
        ensureFill()
    }

    /// Set the offset playback needs filled forward. The loader passes the MAX offset across all of
    /// AVPlayer's active requests, so a resume/seek (e.g. 1.8 GB) wins over the concurrent moov/head
    /// metadata read near offset 0 — the bug that starved the playback region (leadMB negative).
    func setPlayhead(_ offset: Int64) {
        guard offset >= 0, offset != playhead else { return }
        playhead = offset
        ensureFill()
    }

    func stop() {
        fillTask?.cancel()
        fillTask = nil
        contentInfoTask?.cancel()
        contentInfoTask = nil
        streamer.invalidate()
    }

    // MARK: - Fill loop

    private func ensureFill() {
        guard fillTask == nil else { return }
        fillTask = Task { [weak self] in
            await self?.runFill()
        }
    }

    private func runFill() async {
        while !Task.isCancelled {
            if totalLength == nil {
                _ = await contentInfo()
                if totalLength == nil {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
            }
            guard let total = totalLength else { break }

            // Always fill from the first gap at/after the REAL playhead, so the fill follows
            // playback (and seeks) instead of marching from the file head.
            let head = max(0, playhead)
            let start = (try? await store.contiguousEnd(from: head, key: key)) ?? head

            if start >= total {
                // Everything from the playhead to EOF is cached; idle until the playhead moves.
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            // Bounded lookahead: keep ~aheadBudget ahead of the playhead, then idle.
            let lead = start - head
            if lead > aheadBudget {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }

            // Build a batch of contiguous windows to fetch IN PARALLEL — this is what lets the
            // buffer fill fast during a bandwidth burst (single-connection couldn't keep up).
            var windows: [(start: Int64, end: Int64)] = []
            var off = start
            while windows.count < maxParallelWindows, off < total, (off - head) <= aheadBudget {
                windows.append((off, min(off + windowLength, total)))
                off += windowLength
            }
            AppLog.playback.notice(
                "playback.cacheloader.fill.batch — item=\(self.key.itemID.prefix(8), privacy: .public) startMB=\(start / 1_048_576, privacy: .public) endMB=\(off / 1_048_576, privacy: .public) windows=\(windows.count, privacy: .public) headMB=\(head / 1_048_576, privacy: .public) leadMB=\(lead / 1_048_576, privacy: .public)"
            )

            let windowHead = head
            var sawTransient = false
            var sawPermanent = false
            await withTaskGroup(of: WindowResult.self) { group in
                for window in windows {
                    group.addTask { [weak self] in
                        guard let self else { return .cancelled }
                        return await self.runWindow(from: window.start, to: window.end, windowHead: windowHead)
                    }
                }
                for await result in group {
                    switch result {
                    case .transient: sawTransient = true
                    case .permanent: sawPermanent = true
                    case .ok, .cancelled: break
                    }
                }
            }

            if Task.isCancelled { return }
            if sawPermanent {
                AppLog.playback.warning(
                    "playback.cacheloader.fill.stop — item=\(self.key.itemID.prefix(8), privacy: .public) offset=\(start, privacy: .public) reason=permanent_error"
                )
                fillTask = nil
                return
            }
            if sawTransient {
                // A window dropped transiently; committed bytes are in the store. Brief backoff,
                // then the loop recomputes from contiguousEnd(playhead) — no byte re-fetched.
                AppLog.playback.warning(
                    "playback.cacheloader.fill.resume — item=\(self.key.itemID.prefix(8), privacy: .public) headMB=\(head / 1_048_576, privacy: .public) reason=transient_drop"
                )
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private enum WindowResult { case ok, transient, permanent, cancelled }

    /// Runs one window and classifies the outcome (so the parallel batch can react without throwing
    /// across the task group).
    private func runWindow(from start: Int64, to endExclusive: Int64, windowHead: Int64) async -> WindowResult {
        do {
            try await downloadWindow(from: start, to: endExclusive, windowHead: windowHead)
            return .ok
        } catch is ResumableTransferError {
            return .transient
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .permanent
        }
    }

    /// Streams one CLOSED window, committing each sub-block to the store as it arrives. Breaks early
    /// if the playhead jumps out of this window's neighborhood (a seek) so the loop can refollow.
    private func downloadWindow(from start: Int64, to endExclusive: Int64, windowHead: Int64? = nil) async throws {
        guard endExclusive > start else { return }
        var request = URLRequest(url: PlaybackAuthenticatedRequestURL.forInternalURLSession(remoteURL, headers: headers))
        request.httpMethod = "GET"
        request.setValue("bytes=\(start)-\(endExclusive - 1)", forHTTPHeaderField: "Range")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let stream = streamer.stream(request: request, startOffset: start, minSubBlock: minSubBlock)
        for try await block in stream {
            if Task.isCancelled { break }
            // For fill windows (windowHead set): if a seek moved the playhead forward past this
            // window or far back behind it, abandon the rest and let runFill refollow. Prime
            // fetches (windowHead nil — tail/head warm-up) always run to completion.
            if let windowHead, playhead > endExclusive || playhead < windowHead - reanchorDistance { break }
            try await store.write(
                range: ByteRange(offset: block.offset, length: block.data.count),
                data: block.data,
                key: key
            )
        }
    }
}
