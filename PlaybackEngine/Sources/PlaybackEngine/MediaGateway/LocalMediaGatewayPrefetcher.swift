import Foundation
import NativeMediaCore
import Shared
public struct LocalMediaGatewayPrefetchConfiguration: Sendable {
    public var mediaCacheMode: MediaCacheMode
    public var isTVOS: Bool
    public var routeKind: PlaybackMediaCachePolicy.RouteKind
    public var sourceBitrate: Int
    public var runtimeSeconds: TimeInterval
    public var isExpensiveNetwork: Bool
    public var isConstrainedNetwork: Bool

    public init(
        mediaCacheMode: MediaCacheMode,
        isTVOS: Bool,
        routeKind: PlaybackMediaCachePolicy.RouteKind,
        sourceBitrate: Int,
        runtimeSeconds: TimeInterval,
        isExpensiveNetwork: Bool,
        isConstrainedNetwork: Bool
    ) {
        self.mediaCacheMode = mediaCacheMode
        self.isTVOS = isTVOS
        self.routeKind = routeKind
        self.sourceBitrate = sourceBitrate
        self.runtimeSeconds = runtimeSeconds
        self.isExpensiveNetwork = isExpensiveNetwork
        self.isConstrainedNetwork = isConstrainedNetwork
    }
}

enum LocalMediaGatewayPrefetchPriority: Int, Sendable {
    case rangeProbe = 0
    case streamingPlayback = 1
}

actor LocalMediaGatewayPrefetcher {
    private let remoteURL: URL
    private let headers: [String: String]
    private let key: MediaGatewayCacheKey
    private let store: MediaGatewayStore
    private let configuration: LocalMediaGatewayPrefetchConfiguration
    private let session: URLSession
    private let sessionConfiguration: URLSessionConfiguration
    private var activeTask: Task<Void, Never>?
    private var activeTaskStartOffset: Int64?
    private var activeTaskEndOffset: Int64?
    private var activeTaskPriority: LocalMediaGatewayPrefetchPriority?
    private var observedBitrate = 0
    private var knownTotalLength: Int64?
    private var firstScheduleDate: Date?
    private let chunkLength = 1 * 1_024 * 1_024
    private let minimumServedBytesBeforePrefetch = 4
    private let reanchorDistance = 1 * 1_024 * 1_024

    init(
        remoteURL: URL,
        headers: [String: String],
        key: MediaGatewayCacheKey,
        store: MediaGatewayStore,
        configuration: LocalMediaGatewayPrefetchConfiguration,
        sessionConfiguration: URLSessionConfiguration
    ) {
        self.remoteURL = remoteURL
        self.headers = headers
        self.key = key
        self.store = store
        self.configuration = configuration
        sessionConfiguration.networkServiceType = .background
        self.sessionConfiguration = sessionConfiguration.copy() as? URLSessionConfiguration ?? .ephemeral
        self.session = URLSession(configuration: sessionConfiguration)
    }

    func recordRemoteFetch(byteCount: Int, elapsedSeconds: TimeInterval, totalLength: Int64?) {
        if elapsedSeconds > 0 {
            observedBitrate = max(observedBitrate, Int(Double(byteCount * 8) / elapsedSeconds))
        }
        knownTotalLength = totalLength ?? knownTotalLength
    }

    func observedBitrateSnapshot() -> Int {
        observedBitrate
    }

    func diagnosticsSnapshot() -> (
        observedBitrate: Int,
        activeStartOffset: Int64?,
        activeEndOffset: Int64?,
        activePriority: LocalMediaGatewayPrefetchPriority?
    ) {
        (
            observedBitrate,
            activeTaskStartOffset,
            activeTaskEndOffset,
            activeTaskPriority
        )
    }

    nonisolated static func shouldReanchorPrefetch(
        activeStartOffset: Int64?,
        activeEndOffset: Int64? = nil,
        newStartOffset: Int64,
        reanchorDistance: Int64,
        activePriority: LocalMediaGatewayPrefetchPriority,
        newPriority: LocalMediaGatewayPrefetchPriority
    ) -> Bool {
        guard let activeStartOffset else { return true }
        if newPriority.rawValue > activePriority.rawValue { return true }
        if newPriority.rawValue < activePriority.rawValue { return false }
        if newStartOffset < activeStartOffset {
            return activeStartOffset - newStartOffset > reanchorDistance
        }
        if let activeEndOffset {
            guard newStartOffset > activeEndOffset else { return false }
            return newStartOffset - activeEndOffset <= reanchorDistance
        }
        return newStartOffset - activeStartOffset > reanchorDistance
    }

    func schedule(
        after servedRange: ByteRange,
        totalLength: Int64?,
        priority: LocalMediaGatewayPrefetchPriority = .rangeProbe
    ) {
        knownTotalLength = totalLength ?? knownTotalLength
        firstScheduleDate = firstScheduleDate ?? Date()
        guard servedRange.length >= minimumServedBytesBeforePrefetch else { return }
        let startOffset = servedRange.offset + Int64(servedRange.length)
        if let activeTask, !activeTask.isCancelled {
            guard shouldReanchorPrefetch(to: startOffset, priority: priority) else { return }
            activeTask.cancel()
        }
        activeTaskStartOffset = startOffset
        activeTaskPriority = priority
        activeTask = Task { [weak self] in
            await self?.prefetch(startOffset: startOffset)
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        session.invalidateAndCancel()
    }

    private func prefetch(startOffset: Int64) async {
        defer {
            if activeTaskStartOffset == startOffset {
                activeTask = nil
                activeTaskStartOffset = nil
                activeTaskEndOffset = nil
                activeTaskPriority = nil
            }
        }
        guard startOffset >= 0, let targetEnd = await targetEndOffset(from: startOffset), targetEnd > startOffset else { return }
        if activeTaskStartOffset == startOffset {
            activeTaskEndOffset = targetEnd
        }
        AppLog.playback.notice(
            "playback.cache.prefetch.start — item=\(self.key.itemID.prefix(8), privacy: .public) source=\(self.key.sourceID.prefix(8), privacy: .public) start=\(startOffset, privacy: .public) targetEnd=\(targetEnd, privacy: .public)"
        )
        var offset = startOffset
        while offset < targetEnd, !Task.isCancelled {
            let length = Int(min(Int64(chunkLength), targetEnd - offset))
            let range = ByteRange(offset: offset, length: length)
            if await isRangeCached(range) {
                offset += Int64(length)
                continue
            }
            do {
                let fetched = try await fetchAndStore(range: range)
                offset += Int64(max(fetched, length))
            } catch {
                AppLog.playback.warning(
                    "playback.cache.prefetch.stop — item=\(self.key.itemID.prefix(8), privacy: .public) source=\(self.key.sourceID.prefix(8), privacy: .public) offset=\(offset, privacy: .public) reason=\(error.localizedDescription, privacy: .public)"
                )
                return
            }
        }
    }

    private func shouldReanchorPrefetch(
        to startOffset: Int64,
        priority: LocalMediaGatewayPrefetchPriority
    ) -> Bool {
        Self.shouldReanchorPrefetch(
            activeStartOffset: activeTaskStartOffset,
            activeEndOffset: activeTaskEndOffset,
            newStartOffset: startOffset,
            reanchorDistance: Int64(reanchorDistance),
            activePriority: activeTaskPriority ?? .rangeProbe,
            newPriority: priority
        )
    }

    private func targetEndOffset(from startOffset: Int64) async -> Int64? {
        let cachedBytes = ((try? await store.coveredRanges(key: key)) ?? []).reduce(0) { $0 + Int64($1.length) }
        let context = PlaybackMediaCachePolicy.Context(
            platform: configuration.isTVOS ? .tvOS : .iOS,
            mediaCacheMode: configuration.mediaCacheMode,
            routeKind: configuration.routeKind,
            sourceBitrate: max(configuration.sourceBitrate, 1),
            observedBitrate: observedBitrate,
            currentBufferDuration: 0,
            playbackElapsedSeconds: firstScheduleDate.map { Date().timeIntervalSince($0) } ?? 0,
            remainingDuration: configuration.runtimeSeconds,
            isExpensiveNetwork: configuration.isExpensiveNetwork,
            isConstrainedNetwork: configuration.isConstrainedNetwork,
            availableDiskBytes: await store.availableCapacityBytes(),
            activeItemCachedBytes: cachedBytes
        )
        let decision = PlaybackMediaCachePolicy.decision(context: context)
        guard decision.prefetchConcurrency > 0, decision.phase != .paused else { return nil }
        let budgetEnd = startOffset + max(0, decision.maxActiveItemBytes - cachedBytes)
        let aheadBytes = Int64(Double(max(configuration.sourceBitrate, 1)) * decision.targetAheadSeconds / 8)
        let target = decision.allowCompleteItem ? knownTotalLength ?? budgetEnd : startOffset + aheadBytes
        return min(knownTotalLength ?? target, budgetEnd, max(target, startOffset))
    }

    private func isRangeCached(_ range: ByteRange) async -> Bool {
        (try? await store.read(range: range, key: key)) != nil
    }

    private func fetchAndStore(range: ByteRange) async throws -> Int {
        let start = Date()
        var request = URLRequest(url: PlaybackAuthenticatedRequestURL.forInternalURLSession(remoteURL, headers: headers))
        request.httpMethod = "GET"
        request.setValue(Self.upstreamRangeHeader(for: range), forHTTPHeaderField: "Range")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        // Bulk chunked read instead of byte-by-byte AsyncBytes iteration, bounded to the
        // prefetch window so an open-ended upstream response stops at range.length.
        let (payload, http) = try await HTTPChunkedRangeReader.collect(
            request: request,
            configuration: sessionConfiguration.copy() as? URLSessionConfiguration ?? .ephemeral,
            maxLength: range.length
        )
        guard http.statusCode == 206 || (http.statusCode == 200 && range.offset == 0) else {
            throw MediaAccessError.httpStatus(http.statusCode)
        }
        knownTotalLength = http.mediaGatewayContentRangeTotal ?? http.mediaGatewayContentLength ?? knownTotalLength
        try await store.write(range: ByteRange(offset: range.offset, length: payload.count), data: payload, key: key)
        let elapsed = Date().timeIntervalSince(start)
        recordRemoteFetch(byteCount: payload.count, elapsedSeconds: elapsed, totalLength: knownTotalLength)
        return payload.count
    }

    private static func upstreamRangeHeader(for range: ByteRange) -> String {
        if range.offset > 0 {
            return "bytes=\(range.offset)-"
        }
        return "bytes=0-\(range.offset + Int64(range.length) - 1)"
    }
}
