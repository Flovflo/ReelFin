import Foundation
import NativeMediaCore
import Network
import Shared

/// Localhost HTTP/1.1 server that feeds AVPlayer raw original bytes from the `MediaGatewayStore`
/// (filled by the parallel `OriginDownloader`), over an `http://127.0.0.1:port` URL.
///
/// Why this exists: the never-stall cache (`OriginDownloader` + `MediaGatewayStore`) is proven, but
/// delivering it through the custom `reelfin-cache://` resource-loader scheme black-screens Dolby
/// Vision. A plain localhost HTTP URL is indistinguishable from the origin to AVFoundation (native
/// HTTP stack, same MIME override) — so DV renders exactly as in direct play, while AVPlayer reads
/// from the deep local cache instead of the flaky origin. Origin dropouts can no longer drain
/// AVPlayer's buffer, because the buffer is fed from disk: this is the Infuse-class never-cut path.
///
/// The serve path NEVER opens a connection to the origin — that is the downloader's sole job. A
/// request being cancelled (a seek) or AVPlayer closing the connection can never cut playback: the
/// bytes are already on disk or arriving on the downloader's keep-alive parallel connections.
final class LocalCacheHTTPServer: @unchecked Sendable {
    private let store: MediaGatewayStore
    private let downloader: OriginDownloader
    private let key: MediaGatewayCacheKey
    private let overrideMIMEType: String?
    // For low-latency on-demand serving: the serve loop fetches a cache-missed range DIRECTLY from
    // the origin (so AVPlayer's first read / a seek is served at direct-play speed) while the
    // background downloader builds the deep buffer ahead. v1 lacked this and waited on the windowed
    // downloader → 17.5s startup on a deep resume.
    private let remoteURL: URL
    private let headers: [String: String]
    /// Shared, process-lived (see `MediaOriginTransport.onDemand`): the bounded reader installs a
    /// task-specific delegate while preserving H3-broken learning and pooled H2/TLS connections.
    private let onDemandSession = MediaOriginTransport.onDemand

    private let queue = DispatchQueue(label: "reelfin.local-cache-http", attributes: .concurrent)
    private var listener: NWListener?
    private var security: LocalPlaybackServerSecurity?
    private var requiredLocalEndpoint: NWEndpoint?
    private let connectionGate: LocalPlaybackConnectionGate
    private let connectionCallbackHook: (@Sendable () -> Void)?

    private let serveChunk = 4 * 1_024 * 1_024
    /// Socket sends are sliced to this size so a connection AVPlayer already abandoned wastes at
    /// most one slice (a whole 4 MiB serve chunk used to be buffered into the dead socket).
    private let sendSliceBytes = 1_024 * 1_024
    private let pollInterval: UInt64 = 40_000_000      // 40 ms
    private let livenessDeadline: TimeInterval = 20
    /// Close a keep-alive connection that has been IDLE this long (AVPlayer finished with the socket
    /// but never closed it). Without this, the connection's `handle` Task parks forever in the
    /// non-cancellation-aware `receiveRequestHead` continuation and leaks across playback sessions.
    private let idleConnectionTimeout: TimeInterval = 30

    // Every live connection + its handle Task, so `stop()`/`deinit` can FORCE them closed. Cancelling
    // the NWConnection makes its pending `receive` completion fire, which resumes the parked
    // continuation so the Task exits its loop and deregisters. (Cancelling the listener alone left
    // idle keep-alive connections + their Tasks suspended forever → the cross-replay socket/memory
    // leak that produced the "memory warning before the next play starts" → jetsam.)
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
    private var connectionTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var connectionLeases: [ObjectIdentifier: LocalPlaybackConnectionGate.Lease] = [:]
    private var acceptingConnections = false
    private var generation = 0
    private var receiveStartCount = 0

    // Per active serve loop: its current offset + whether it is STARVED (waiting for bytes not yet
    // cached). The downloader fills the lowest starved offset first (unblock the most-behind reader —
    // moov/metadata at startup, playback after), and only builds cushion ahead of the furthest
    // reader when nothing is starved. This is what stops a concurrent metadata read near offset 0
    // from yanking the fill back to the file head while playback needs bytes far ahead.
    private let lock = NSLock()
    private var activeServes: [UUID: (offset: Int64, waiting: Bool)] = [:]

    init(
        store: MediaGatewayStore,
        downloader: OriginDownloader,
        key: MediaGatewayCacheKey,
        remoteURL: URL,
        headers: [String: String],
        overrideMIMEType: String?,
        connectionCapacity: Int? = LocalPlaybackServerSecurity.defaultConnectionCapacity,
        connectionGate: LocalPlaybackConnectionGate? = nil,
        connectionCallbackHook: (@Sendable () -> Void)? = nil
    ) {
        self.store = store
        self.downloader = downloader
        self.key = key
        self.remoteURL = remoteURL
        self.headers = headers
        self.overrideMIMEType = overrideMIMEType
        self.connectionGate = connectionGate ?? LocalPlaybackConnectionGate(capacity: connectionCapacity)
        self.connectionCallbackHook = connectionCallbackHook
    }

    /// Starts the listener and returns the localhost URL AVPlayer should play.
    func start() throws -> URL {
        let security = LocalPlaybackServerSecurity()
        let configuredListener = try LocalPlaybackServerSecurity.makeLoopbackListener()
        let listener = configuredListener.listener
        let startedGeneration = lock.withLock { () -> Int in
            generation += 1
            acceptingConnections = true
            receiveStartCount = 0
            self.listener = listener
            self.security = security
            requiredLocalEndpoint = configuredListener.requiredLocalEndpoint
            return generation
        }
        let ready = DispatchSemaphore(value: 0)
        var startError: Error?
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            self.connectionCallbackHook?()
            self.handle(connection, generation: startedGeneration)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let error): startError = error; ready.signal()
            default: break
            }
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 4)
        if let startError {
            clearStartup(listener: listener, generation: startedGeneration)
            listener.cancel()
            throw startError
        }
        guard let port = listener.port,
              let baseURL = security.baseURL(port: port) else {
            clearStartup(listener: listener, generation: startedGeneration)
            listener.cancel()
            throw MediaAccessError.cannotDetermineSize
        }
        guard lock.withLock({ acceptingConnections && generation == startedGeneration && self.listener === listener }) else {
            listener.cancel()
            throw CancellationError()
        }
        return baseURL.appendingPathComponent("media")
    }

    func stop(reason: String) {
        let drained = lock.withLock { () -> (NWListener?, [NWConnection], [Task<Void, Never>], [LocalPlaybackConnectionGate.Lease]) in
            acceptingConnections = false
            let result = (
                listener,
                Array(activeConnections.values),
                Array(connectionTasks.values),
                Array(connectionLeases.values)
            )
            listener = nil
            security = nil
            requiredLocalEndpoint = nil
            activeConnections.removeAll()
            connectionTasks.removeAll()
            connectionLeases.removeAll()
            return result
        }
        drained.0?.cancel()
        // Cancelling the connection unblocks its parked `receive` → the handle Task exits its loop.
        for connection in drained.1 { connection.cancel() }
        for task in drained.2 { task.cancel() }
        for lease in drained.3 { lease.release() }
        // The process-shared origin session deliberately outlives this local server. Each bounded
        // reader still cancels its own task when the serve is cancelled or its window is complete.
        // Capture the downloader value (NOT self) so this escaping Task is safe to spawn from deinit.
        let downloader = self.downloader
        Task { await downloader.stop() }
    }

    deinit {
        // Safety net if stop() was never called. Cancel transport synchronously; do NOT touch self in
        // an escaping Task during deallocation (that crashes) — capture the downloader value instead.
        let drained = lock.withLock { () -> (NWListener?, [NWConnection], [Task<Void, Never>], [LocalPlaybackConnectionGate.Lease]) in
            acceptingConnections = false
            let result = (
                listener,
                Array(activeConnections.values),
                Array(connectionTasks.values),
                Array(connectionLeases.values)
            )
            listener = nil
            security = nil
            activeConnections.removeAll()
            connectionTasks.removeAll()
            connectionLeases.removeAll()
            return result
        }
        drained.0?.cancel()
        for connection in drained.1 { connection.cancel() }
        for task in drained.2 { task.cancel() }
        for lease in drained.3 { lease.release() }
        // onDemandSession is process-shared and is intentionally not invalidated here.
        let downloader = self.downloader
        Task { await downloader.stop() }
    }

#if DEBUG
    /// Test hook: number of connections the server is currently tracking (must return to 0 after stop).
    var debugActiveConnectionCount: Int { lock.lock(); defer { lock.unlock() }; return activeConnections.count }
    var debugConnectionSnapshot: LocalPlaybackConnectionGate.Snapshot { connectionGate.snapshot }
    var debugRequiredLocalEndpoint: NWEndpoint? { lock.withLock { requiredLocalEndpoint } }
    var debugConnectionTaskCount: Int { lock.withLock { connectionTasks.count } }
    var debugReceiveStartCount: Int { lock.withLock { receiveStartCount } }
#endif

    // MARK: - Connection handling

    private func clearStartup(listener expectedListener: NWListener, generation expectedGeneration: Int) {
        lock.withLock {
            guard generation == expectedGeneration, listener === expectedListener else { return }
            acceptingConnections = false
            listener = nil
            security = nil
            requiredLocalEndpoint = nil
        }
    }

    private func isCurrent(generation expectedGeneration: Int) -> Bool {
        lock.withLock { acceptingConnections && generation == expectedGeneration }
    }

    private func beginReceive(id: ObjectIdentifier, generation expectedGeneration: Int) -> Bool {
        lock.withLock {
            guard acceptingConnections, generation == expectedGeneration,
                  activeConnections[id] != nil,
                  connectionTasks[id] != nil else { return false }
            receiveStartCount += 1
            return true
        }
    }

    private func finishConnection(id: ObjectIdentifier, connection: NWConnection) {
        connection.cancel()
        let lease = lock.withLock { () -> LocalPlaybackConnectionGate.Lease? in
            activeConnections[id] = nil
            connectionTasks[id] = nil
            return connectionLeases.removeValue(forKey: id)
        }
        lease?.release()
    }

    private func handle(_ connection: NWConnection, generation expectedGeneration: Int) {
        let cid = ObjectIdentifier(connection)
        let idleTimeout = idleConnectionTimeout
        let admitted = lock.withLock { () -> Bool in
            guard acceptingConnections, generation == expectedGeneration,
                  let lease = connectionGate.acquire() else { return false }
            activeConnections[cid] = connection
            connectionLeases[cid] = lease
            connection.start(queue: queue)
            let task = Task { [weak self] in
                let cleanup: @Sendable () -> Void = { [weak self] in
                    connection.cancel()
                    guard let self else {
                        lease.release()
                        return
                    }
                    self.finishConnection(id: cid, connection: connection)
                }
                defer { cleanup() }
                // HTTP/1.1 keep-alive: serve sequential requests on ONE connection so AVPlayer reuses a
                // single socket for its ranged reads (instead of opening a new connection per range — which
                // spawned hundreds of active serves and thrashed the downloader's playhead). Loop until the
                // client closes the socket or a serve says the connection can't continue.
                while !Task.isCancelled {
                    guard self?.beginReceive(id: cid, generation: expectedGeneration) == true else { return }
                    // An idle keep-alive socket (AVPlayer done with it but not closed) must NOT park this
                    // Task forever — cancelling the tracked connection during stop resumes this receive.
                    let requestData = await Self.receiveRequestHead(
                        connection,
                        idleTimeout: idleTimeout
                    )
                    guard !Task.isCancelled,
                          self?.isCurrent(generation: expectedGeneration) == true,
                          let requestData else {
                        return // client closed the connection / idle-timed-out / cancelled
                    }
                    guard let request = LocalMediaGatewayHTTPRequest(requestData) else {
                        guard let self else { return }
                        await self.trySend(LocalMediaGatewayHTTPResponse.badRequest(), over: connection)
                        return
                    }
                    guard let keepAlive = await self?.serve(
                        request,
                        over: connection,
                        generation: expectedGeneration
                    ) else { return }
                    if !keepAlive { return }
                }
            }
            connectionTasks[cid] = task
            return true
        }
        if !admitted {
            connection.cancel()
        }
    }

    /// Accumulate bytes until the end of the HTTP header block (`\r\n\r\n`). GET/HEAD have no body,
    /// so that is the whole request.
    private static func receiveRequestHead(
        _ connection: NWConnection,
        idleTimeout: TimeInterval
    ) async -> Data? {
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: UInt64(idleTimeout * 1_000_000_000))
            // Only fire if we actually reached the timeout. When a request arrives we cancel
            // this watchdog, which makes the sleep throw — must NOT then close the live socket.
            if !Task.isCancelled { connection.cancel() }
        }
        defer { watchdog.cancel() }
        var buffer = Data()
        let terminator = Data("\r\n\r\n".utf8)
        while buffer.count < 64 * 1_024 {
            let chunk: Data? = await withCheckedContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1_024) { data, _, isComplete, _ in
                    if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(returning: isComplete ? nil : Data())
                    }
                }
            }
            guard let chunk else { return buffer.isEmpty ? nil : buffer }
            buffer.append(chunk)
            if buffer.range(of: terminator) != nil { return buffer }
            if chunk.isEmpty { try? await Task.sleep(nanoseconds: 5_000_000) }
        }
        return buffer
    }

    /// Serves one request. Returns whether the connection may be REUSED for a subsequent request
    /// (keep-alive): `true` only when the full response was delivered, `false` when AVPlayer closed
    /// mid-stream or an error response ended the connection.
    private func serve(
        _ request: LocalMediaGatewayHTTPRequest,
        over connection: NWConnection,
        generation expectedGeneration: Int
    ) async -> Bool {
        let security = lock.withLock { () -> LocalPlaybackServerSecurity? in
            guard acceptingConnections, generation == expectedGeneration else { return nil }
            return self.security
        }
        guard security?.authorizedResourcePath(for: request.path) == "/media" else {
            await trySend(LocalMediaGatewayHTTPResponse.notFound(), over: connection)
            return false
        }

        // NEVER park a serve behind the origin probe's retry ladder (~2 min worst case): known info
        // first (memory / persisted), then ONE bounded on-demand fetch whose 206 Content-Range
        // answers both "how big" and the first bytes (written to the store → the body loop hits
        // cache), then a BOUNDED wait on the background probe. AVPlayer's very first byte request
        // rode the full ladder before — the black-screen minutes when the origin was flaky.
        var (total, resolvedType) = await downloader.knownContentInfo()
        if total == nil {
            let unresolvedOffset = initialOffset(for: request.range)
            let probeStart = unresolvedOffset.flatMap {
                checkedInclusiveEnd(from: $0, length: serveChunk) == nil ? nil : $0
            } ?? 0
            var primed = await fetchRangeOnDemandDetailed(from: probeStart, length: serveChunk)
            if primed == nil, probeStart != 0 {
                primed = await fetchRangeOnDemandDetailed(from: 0, length: serveChunk)
            }
            if let primed {
                if let discovered = primed.total {
                    await downloader.adoptContentInfo(total: discovered, contentType: primed.contentType)
                    total = discovered
                    if resolvedType == nil { resolvedType = primed.contentType }
                }
            }
        }
        if total == nil {
            let deadline = Date().addingTimeInterval(livenessDeadline)
            while Date() < deadline, !Task.isCancelled {
                let known = await downloader.knownContentInfo()
                if let length = known.length {
                    total = length
                    if resolvedType == nil { resolvedType = known.contentType }
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        guard let total, total > 0 else {
            await trySend(LocalMediaGatewayHTTPResponse.serverError(), over: connection)
            return false
        }
        let contentType = overrideMIMEType ?? resolvedType

        if request.method == "HEAD" {
            return await trySend(LocalMediaGatewayHTTPResponse.head(totalLength: total, contentType: contentType, keepAlive: true), over: connection)
        }
        guard request.method == "GET" else {
            await trySend(LocalMediaGatewayHTTPResponse.badRequest(), over: connection)
            return false
        }

        let resolvedRange: LocalMediaGatewayResolvedRange?
        if let requestedRange = request.range {
            resolvedRange = requestedRange.resolve(totalLength: total)
        } else {
            resolvedRange = LocalMediaGatewayResolvedRange(start: 0, endExclusive: total)
        }
        guard let resolvedRange else {
            await trySend(LocalMediaGatewayHTTPResponse.rangeNotSatisfiable(totalLength: total), over: connection)
            return false
        }

        let header = LocalMediaGatewayHTTPResponse.partialHeaders(
            range: resolvedRange,
            totalLength: total,
            contentType: contentType,
            keepAlive: true
        )
        guard await trySend(header, over: connection) else { return false }

        return await streamBody(from: resolvedRange.start, to: resolvedRange.endExclusive, over: connection)
    }

    /// Streams `[start, end)` from the cache, waiting for the downloader to fill any gap. Mirrors the
    /// proven `CacheResourceLoaderDelegate.serve` loop, but writes to the socket instead of an
    /// `AVAssetResourceLoadingDataRequest`.
    /// Returns `true` if the full `[start, end)` range was delivered (so the connection can be kept
    /// alive for the next request), `false` if AVPlayer closed mid-stream or the serve timed out.
    private func streamBody(from start: Int64, to end: Int64, over connection: NWConnection) async -> Bool {
        let id = UUID()
        defer { finishServe(id) }
        var offset = start
        var lastProgress = Date()
        // Diagnostics: only the serves that MISS the cache / hit the origin are logged (so the noise
        // floor stays low). This is how we see whether AVPlayer is reading cached bytes or landing in
        // a gap that needs the origin (the "deep cache but it still stalls" question).
        var hitBytes: Int64 = 0
        var onDemandBytes: Int64 = 0
        var onDemandFails = 0
        var originDown = false
        func logEnd(_ reason: String, ok: Bool) {
            guard onDemandBytes > 0 || onDemandFails > 0 || !ok else { return }
            AppLog.playback.notice(
                "playback.cachehttp.serve.end — item=\(self.key.itemID.prefix(8), privacy: .public) startMB=\(start / 1_048_576, privacy: .public) reachedMB=\(offset / 1_048_576, privacy: .public) hitKB=\(hitBytes / 1024, privacy: .public) onDemandKB=\(onDemandBytes / 1024, privacy: .public) onDemandFail=\(onDemandFails, privacy: .public) reason=\(reason, privacy: .public)"
            )
        }
        while offset < end {
            let want = Int(min(Int64(serveChunk), end - offset))
            // 1. Cache hit — serve instantly from the deep local buffer (survives origin dropouts).
            if want > 0,
               let data = try? await store.readAvailablePrefix(from: offset, maxLength: want, key: key),
               !data.isEmpty {
                await publish(id: id, offset: offset, waiting: false)
                guard await sendSliced(data, over: connection) else { logEnd("client_closed", ok: false); return false }
                offset += Int64(data.count)
                hitBytes += Int64(data.count)
                lastProgress = Date()
                continue
            }
            // Mark the playhead so the background downloader builds the deep cushion from here.
            await publish(id: id, offset: offset, waiting: true)
            // 2. Cache miss — fetch this exact range DIRECTLY (low latency, = direct-play speed for
            // the first read / a seek) instead of waiting for the windowed downloader. The result is
            // written to the store so it is cached for any re-read. Once the origin has clearly failed
            // (a timeout), STOP re-hammering it on every 40 ms poll — just wait for the background
            // downloader/cache, so an origin outage doesn't block this serve for 15 s per iteration.
            if want > 0, !originDown, let data = await fetchRangeOnDemand(from: offset, length: want), !data.isEmpty {
                guard await sendSliced(data, over: connection) else { logEnd("client_closed", ok: false); return false }
                offset += Int64(data.count)
                onDemandBytes += Int64(data.count)
                lastProgress = Date()
                continue
            }
            if want > 0, !originDown {
                onDemandFails += 1
                originDown = true // origin unreachable for this serve → fall back to cache-only polling
            }
            // 3. Origin can't serve this byte right now — wait for the background downloader to fill it
            // from cache; close on a genuinely sustained outage so AVPlayer surfaces a stall and the
            // session's recovery path takes over.
            if Date().timeIntervalSince(lastProgress) > livenessDeadline {
                logEnd("liveness_timeout", ok: false)
                AppLog.playback.warning(
                    "playback.cachehttp.serve.liveness_timeout — item=\(self.key.itemID.prefix(8), privacy: .public) offsetMB=\(offset / 1_048_576, privacy: .public)"
                )
                return false
            }
            // Cache-only polling now: the background downloader keeps retrying the origin on its own,
            // so if it recovers the next poll will hit the cache. We don't re-hammer on-demand here.
            try? await Task.sleep(nanoseconds: pollInterval)
        }
        logEnd("complete", ok: true)
        return true
    }

    /// Fetches `[from, from+length)` directly from the origin (a single ranged GET), writes it to
    /// the store, and returns it. Used to serve a cache miss at direct-play latency. Returns nil on
    /// any failure (a dropout) so the caller falls back to waiting for the background downloader.
    private func fetchRangeOnDemand(from: Int64, length: Int) async -> Data? {
        await fetchRangeOnDemandDetailed(from: from, length: length)?.data
    }

    /// Same fetch, exposing what the response HEADERS reveal: a 206's `Content-Range` carries the
    /// file's TOTAL length — so the very first serve can adopt content info from the same request
    /// that fetched its first bytes, instead of waiting on the dedicated probe.
    private func fetchRangeOnDemandDetailed(from: Int64, length: Int) async -> (data: Data, total: Int64?, contentType: String?)? {
        guard let endInclusive = checkedInclusiveEnd(from: from, length: length) else { return nil }
        var request = URLRequest(url: PlaybackAuthenticatedRequestURL.forInternalURLSession(remoteURL, headers: headers))
        request.httpMethod = "GET"
        request.setValue("bytes=\(from)-\(endInclusive)", forHTTPHeaderField: "Range")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        do {
            let (data, http) = try await HTTPChunkedRangeReader.collect(
                request: request,
                session: onDemandSession,
                maxLength: length,
                responseValidator: { response in
                    Self.acceptsOnDemandResponse(
                        response,
                        requestedStart: from,
                        requestedEndInclusive: endInclusive
                    )
                }
            )
            guard !data.isEmpty else {
                return nil
            }
            try? await store.write(range: ByteRange(offset: from, length: data.count), data: data, key: key)
            // A 200 means the server ignored the range and its Content-Length IS the file size;
            // a 206's Content-Length is only the window, so total must come from Content-Range.
            let total = http.mediaGatewayContentRangeTotal
                ?? (http.statusCode == 200 ? http.mediaGatewayContentLength : nil)
            return (data, total, http.value(forHTTPHeaderField: "Content-Type"))
        } catch {
            return nil
        }
    }

    /// Rejects a mismatched origin response before URLSession delivers any body bytes. A 206 may
    /// advertise a larger interval than our internal fetch window, but it must start at the byte we
    /// requested and cover the window (or end at the checked resource EOF). The reader cancels after
    /// exactly `length` bytes.
    private static func acceptsOnDemandResponse(
        _ response: HTTPURLResponse,
        requestedStart: Int64,
        requestedEndInclusive: Int64
    ) -> Bool {
        if response.statusCode == 200 { return requestedStart == 0 }
        guard response.statusCode == 206,
              let raw = response.value(forHTTPHeaderField: "Content-Range"),
              let space = raw.firstIndex(of: " "),
              raw[..<space].lowercased() == "bytes",
              let slash = raw.lastIndex(of: "/"),
              space < slash,
              let dash = raw[raw.index(after: space)..<slash].firstIndex(of: "-"),
              let start = Int64(raw[raw.index(after: space)..<dash]),
              let end = Int64(raw[raw.index(after: dash)..<slash]),
              start == requestedStart,
              end >= start else {
            return false
        }
        let totalToken = raw[raw.index(after: slash)...]
        let total = Int64(totalToken)
        guard totalToken == "*" || total != nil else { return false }
        if let total {
            guard total > end else { return false }
        }
        if end >= requestedEndInclusive { return true }
        guard let total else { return false }
        let (lastResourceByte, underflow) = total.subtractingReportingOverflow(1)
        return !underflow && end == lastResourceByte
    }

    private func checkedInclusiveEnd(from: Int64, length: Int) -> Int64? {
        guard from >= 0, length > 0, let semanticLength = Int64(exactly: length) else { return nil }
        let (distance, subtractionOverflow) = semanticLength.subtractingReportingOverflow(1)
        guard !subtractionOverflow else { return nil }
        let (endInclusive, additionOverflow) = from.addingReportingOverflow(distance)
        guard !additionOverflow else { return nil }
        return endInclusive
    }

    /// First byte offset a request needs, when it is knowable WITHOUT the file's total length
    /// (a suffix range needs the total first — rare from AVPlayer, handled by the probe path).
    private func initialOffset(for range: LocalMediaGatewayRequestedRange?) -> Int64? {
        switch range {
        case .bounded(let r): return r.offset
        case .openEnded(let offset): return offset
        case .suffix: return nil
        case nil: return 0
        }
    }

    // MARK: - Downloader playhead targeting

    private func publish(id: UUID, offset: Int64, waiting: Bool) async {
        lock.lock()
        activeServes[id] = (offset, waiting)
        let target = downloaderTargetLocked()
        lock.unlock()
        if let target { await downloader.setPlayhead(target) }
    }

    private func finishServe(_ id: UUID) {
        lock.lock()
        activeServes[id] = nil
        let target = downloaderTargetLocked()
        lock.unlock()
        if let target {
            Task { await downloader.setPlayhead(target) }
        }
    }

    /// Caller must hold `lock`. Lowest starved offset (unblock the most-behind reader), else the
    /// furthest active offset (build cushion ahead of playback).
    private func downloaderTargetLocked() -> Int64? {
        let starved = activeServes.values.filter { $0.waiting }.map { $0.offset }
        if let lowestStarved = starved.min() { return lowestStarved }
        return activeServes.values.map { $0.offset }.max()
    }

    // MARK: - Socket send

    @discardableResult
    private func trySend(_ data: Data, over connection: NWConnection) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            connection.send(content: data, completion: .contentProcessed { error in
                continuation.resume(returning: error == nil)
            })
        }
    }

    /// Sends in `sendSliceBytes` pieces, aborting on the first failed slice — a closed socket is
    /// detected within one slice instead of after buffering a whole serve chunk into it.
    private func sendSliced(_ data: Data, over connection: NWConnection) async -> Bool {
        if data.count <= sendSliceBytes { return await trySend(data, over: connection) }
        var index = data.startIndex
        while index < data.endIndex {
            let end = data.index(index, offsetBy: sendSliceBytes, limitedBy: data.endIndex) ?? data.endIndex
            guard await trySend(data.subdata(in: index ..< end), over: connection) else { return false }
            index = end
        }
        return true
    }
}
