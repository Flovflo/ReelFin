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
    private let pathToken: String
    // For low-latency on-demand serving: the serve loop fetches a cache-missed range DIRECTLY from
    // the origin (so AVPlayer's first read / a seek is served at direct-play speed) while the
    // background downloader builds the deep buffer ahead. v1 lacked this and waited on the windowed
    // downloader → 17.5s startup on a deep resume.
    private let remoteURL: URL
    private let headers: [String: String]
    private let onDemandSession: URLSession

    private let queue = DispatchQueue(label: "reelfin.local-cache-http", attributes: .concurrent)
    private var listener: NWListener?

    private let serveChunk = 4 * 1_024 * 1_024
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
        onDemandTimeout: TimeInterval = 15
    ) {
        self.store = store
        self.downloader = downloader
        self.key = key
        self.remoteURL = remoteURL
        self.headers = headers
        self.overrideMIMEType = overrideMIMEType
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = onDemandTimeout
        config.timeoutIntervalForResource = onDemandTimeout * 2
        config.httpMaximumConnectionsPerHost = 4
        self.onDemandSession = URLSession(configuration: config)
        // Opaque, stable path so the URL is extensionless (the asset's overrideMIMEType supplies the
        // type, exactly like the extensionless direct-play origin URL).
        self.pathToken = "media/\(key.itemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "item")"
    }

    /// Starts the listener and returns the localhost URL AVPlayer should play.
    func start() throws -> URL {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        var startError: Error?
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let error): startError = error; ready.signal()
            default: break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 4)
        if let startError { throw startError }
        guard let port = listener.port else { throw MediaAccessError.cannotDetermineSize }
        guard let url = URL(string: "http://127.0.0.1:\(port.rawValue)/\(pathToken)") else {
            throw MediaAccessError.cannotDetermineSize
        }
        return url
    }

    func stop(reason: String) {
        listener?.cancel()
        listener = nil
        lock.lock()
        let conns = Array(activeConnections.values)
        let tasks = Array(connectionTasks.values)
        activeConnections.removeAll()
        connectionTasks.removeAll()
        lock.unlock()
        // Cancelling the connection unblocks its parked `receive` → the handle Task exits its loop.
        for connection in conns { connection.cancel() }
        for task in tasks { task.cancel() }
        // Capture the downloader value (NOT self) so this escaping Task is safe to spawn from deinit.
        let downloader = self.downloader
        Task { await downloader.stop() }
    }

    deinit {
        // Safety net if stop() was never called. Cancel transport synchronously; do NOT touch self in
        // an escaping Task during deallocation (that crashes) — capture the downloader value instead.
        listener?.cancel()
        lock.lock()
        let conns = Array(activeConnections.values)
        let tasks = Array(connectionTasks.values)
        activeConnections.removeAll()
        connectionTasks.removeAll()
        lock.unlock()
        for connection in conns { connection.cancel() }
        for task in tasks { task.cancel() }
        let downloader = self.downloader
        Task { await downloader.stop() }
    }

#if DEBUG
    /// Test hook: number of connections the server is currently tracking (must return to 0 after stop).
    var debugActiveConnectionCount: Int { lock.lock(); defer { lock.unlock() }; return activeConnections.count }
#endif

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        let cid = ObjectIdentifier(connection)
        lock.lock(); activeConnections[cid] = connection; lock.unlock()
        let task = Task { [weak self] in
            guard let self else { connection.cancel(); return }
            // Deregister + close when this connection's serving ends (client closed, error, or
            // cancellation from stop()). This is what frees the socket + Task — no cross-session leak.
            defer {
                connection.cancel()
                self.lock.lock()
                self.activeConnections[cid] = nil
                self.connectionTasks[cid] = nil
                self.lock.unlock()
            }
            // HTTP/1.1 keep-alive: serve sequential requests on ONE connection so AVPlayer reuses a
            // single socket for its ranged reads (instead of opening a new connection per range — which
            // spawned hundreds of active serves and thrashed the downloader's playhead). Loop until the
            // client closes the socket or a serve says the connection can't continue.
            while !Task.isCancelled {
                // An idle keep-alive socket (AVPlayer done with it but not closed) must NOT park this
                // Task forever — `receiveRequestHead`'s `receive` continuation is not cancellation-aware,
                // so we cancel the connection after an idle timeout, which makes the receive complete.
                let watchdog = Task { [idleConnectionTimeout] in
                    try? await Task.sleep(nanoseconds: UInt64(idleConnectionTimeout * 1_000_000_000))
                    // Only fire if we actually reached the timeout. When a request arrives we cancel
                    // this watchdog, which makes the sleep throw — must NOT then close the live socket.
                    if !Task.isCancelled { connection.cancel() }
                }
                let requestData = await self.receiveRequestHead(connection)
                watchdog.cancel()
                guard let requestData else {
                    return // client closed the connection / idle-timed-out / cancelled
                }
                guard let request = LocalMediaGatewayHTTPRequest(requestData) else {
                    await self.trySend(LocalMediaGatewayHTTPResponse.badRequest(), over: connection)
                    return
                }
                let keepAlive = await self.serve(request, over: connection)
                if !keepAlive { return }
            }
        }
        lock.lock(); connectionTasks[cid] = task; lock.unlock()
    }

    /// Accumulate bytes until the end of the HTTP header block (`\r\n\r\n`). GET/HEAD have no body,
    /// so that is the whole request.
    private func receiveRequestHead(_ connection: NWConnection) async -> Data? {
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
    private func serve(_ request: LocalMediaGatewayHTTPRequest, over connection: NWConnection) async -> Bool {
        let (total, resolvedType) = await downloader.contentInfo()
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

        let (start, end) = byteRange(for: request.range, total: total)
        guard start >= 0, start < total, end > start else {
            await trySend(LocalMediaGatewayHTTPResponse.rangeNotSatisfiable(totalLength: total), over: connection)
            return false
        }

        let header = LocalMediaGatewayHTTPResponse.partialHeaders(
            range: ByteRange(offset: start, length: Int(end - start)),
            totalLength: total,
            contentType: contentType,
            keepAlive: true
        )
        guard await trySend(header, over: connection) else { return false }

        return await streamBody(from: start, to: end, over: connection)
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
                guard await trySend(data, over: connection) else { logEnd("client_closed", ok: false); return false }
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
                guard await trySend(data, over: connection) else { logEnd("client_closed", ok: false); return false }
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
        guard length > 0 else { return nil }
        var request = URLRequest(url: PlaybackAuthenticatedRequestURL.forInternalURLSession(remoteURL, headers: headers))
        request.httpMethod = "GET"
        request.setValue("bytes=\(from)-\(from + Int64(length) - 1)", forHTTPHeaderField: "Range")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        do {
            let (data, response) = try await onDemandSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 206 || http.statusCode == 200, !data.isEmpty else {
                return nil
            }
            try? await store.write(range: ByteRange(offset: from, length: data.count), data: data, key: key)
            return data
        } catch {
            return nil
        }
    }

    private func byteRange(for range: LocalMediaGatewayRequestedRange?, total: Int64) -> (Int64, Int64) {
        switch range {
        case .bounded(let r):
            return (r.offset, min(total, r.offset + Int64(r.length)))
        case .openEnded(let offset):
            return (offset, total)
        case .suffix(let length):
            return (max(0, total - Int64(length)), total)
        case nil:
            return (0, total)
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
}
