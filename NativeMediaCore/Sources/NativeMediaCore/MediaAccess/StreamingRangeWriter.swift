import Foundation

/// Classifies URL-loading errors that a *resumable* range transfer should retry (the connection
/// dropped but the bytes are still there) versus give up on (the request itself is malformed or
/// the resource is gone).
public enum MediaTransferRetry {
    /// Transient transport failures that warrant resuming from the last committed offset.
    /// These are exactly the codes that caused the residual playback cuts: connection lost
    /// (-1005), timed out (-1001), not-connected (-1009), secure-connection failed (-1200),
    /// cannot-connect (-1004), dns (-1003/-1006).
    public static func isTransient(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch nsError.code {
        case NSURLErrorNetworkConnectionLost,
             NSURLErrorTimedOut,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorSecureConnectionFailed,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorResourceUnavailable,
             NSURLErrorRequestBodyStreamExhausted:
            return true
        default:
            return false
        }
    }
}

/// Raised when a range transfer fails on a *transient* transport error after some bytes were
/// already committed. The consumer resumes a fresh closed-range request from its own committed
/// counter (the store is the authority); `lastCommittedOffset` is the streamer's best-effort echo.
public struct ResumableTransferError: Error, Sendable {
    public let lastCommittedOffset: Int64
    public let underlying: Error
    public init(lastCommittedOffset: Int64, underlying: Error) {
        self.lastCommittedOffset = lastCommittedOffset
        self.underlying = underlying
    }
}

/// A persistent, keep-alive HTTP connection that streams CLOSED byte ranges and hands each
/// committed-as-you-go ≥`minSubBlock` slice to its consumer the instant it arrives.
///
/// This is the load-bearing never-cut mechanism. Two properties make it different from
/// `HTTPChunkedRangeReader` (which is correct only for one-shot bounded probes):
///
/// 1. **One `URLSession` for the whole playback session.** Every window reuses the same session,
///    so sequential closed-range GETs ride the same keep-alive TCP/TLS connection instead of
///    paying a handshake (and a connection-churn micro-stall) per window. `HTTPChunkedRangeReader`
///    cancels its task at `maxLength`, which closes the connection — the churn we are removing.
/// 2. **Commit-as-you-go with resumable errors.** Sub-blocks are emitted as `didReceive data`
///    fires; on a transient drop the buffered tail is flushed and a `ResumableTransferError` is
///    raised so the consumer resumes from exactly what it already has — no byte is re-fetched.
///
/// Lifetime is owned by the consumer (`OriginDownloader`), never by an AVPlayer serve request.
/// Breaking out of a stream's iteration cancels ONLY that window's task; the session (and its
/// keep-alive connection) survives for the next window.
public final class StreamingRangeWriter: NSObject, @unchecked Sendable {
    public struct SubBlock: Sendable {
        public let offset: Int64
        public let data: Data
    }

    private final class TaskState {
        let startOffset: Int64
        let minSubBlock: Int
        let continuation: AsyncThrowingStream<SubBlock, Error>.Continuation
        var buffer = Data()
        var emittedEnd: Int64
        var finished = false
        init(
            startOffset: Int64,
            minSubBlock: Int,
            continuation: AsyncThrowingStream<SubBlock, Error>.Continuation
        ) {
            self.startOffset = startOffset
            self.minSubBlock = minSubBlock
            self.emittedEnd = startOffset
            self.continuation = continuation
        }
    }

    private let lock = NSLock()
    private var states: [Int: TaskState] = [:]
    private var session: URLSession!
    private var invalidated = false

    public init(configuration: URLSessionConfiguration) {
        super.init()
        let cfg = (configuration.copy() as? URLSessionConfiguration) ?? URLSessionConfiguration.ephemeral
        // Parallel range requests: a single connection to this Cloudflare origin tops out far
        // below what the link can burst (measured: 1 conn ≈ 28-30 Mbps vs AVPlayer ≈ 232 Mbps).
        // Multiple connections saturate the bursts so the downloader can build a deep buffer
        // (the Infuse approach) and ride out the dropouts.
        cfg.httpMaximumConnectionsPerHost = 8
        self.session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    /// Streams the CLOSED range carried by `request` (its `Range` header must be
    /// `bytes={startOffset}-{end}`). Sub-blocks arrive in order. Cancelling iteration (or
    /// dropping the iterator) cancels only this window's task; the session lives on.
    public func stream(
        request: URLRequest,
        startOffset: Int64,
        minSubBlock: Int = 256 * 1_024
    ) -> AsyncThrowingStream<SubBlock, Error> {
        let (stream, continuation) = AsyncThrowingStream<SubBlock, Error>.makeStream(bufferingPolicy: .unbounded)
        // Create the task UNDER the lock and gated on `invalidated`, atomically with the flag that
        // invalidate() sets. This prevents the crash "Task created in a session that has been
        // invalidated" when teardown (recovery) races with the parallel fill launching a window.
        lock.lock()
        if invalidated {
            lock.unlock()
            continuation.finish(throwing: MediaAccessError.cancelled)
            return stream
        }
        let task = session.dataTask(with: request)
        let state = TaskState(startOffset: startOffset, minSubBlock: max(1, minSubBlock), continuation: continuation)
        states[task.taskIdentifier] = state
        lock.unlock()
        continuation.onTermination = { [weak self] _ in
            task.cancel()
            self?.removeState(task.taskIdentifier)
        }
        task.resume()
        return stream
    }

    /// Tears down the session and all in-flight windows. Call once at end of playback. Sets the
    /// `invalidated` flag (under the lock) BEFORE invalidating the session so any concurrent
    /// `stream()` either created its task already (it gets cancelled) or sees the flag and creates
    /// none — never a task on the invalidated session.
    public func invalidate() {
        lock.lock()
        invalidated = true
        lock.unlock()
        session.invalidateAndCancel()
    }

    private func removeState(_ identifier: Int) {
        lock.lock()
        states[identifier] = nil
        lock.unlock()
    }
}

extension StreamingRangeWriter: URLSessionDataDelegate {
    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        guard let state = states[dataTask.taskIdentifier], !state.finished else {
            lock.unlock()
            completionHandler(.cancel)
            return
        }
        let startOffset = state.startOffset
        lock.unlock()

        guard let http = response as? HTTPURLResponse else {
            finish(taskIdentifier: dataTask.taskIdentifier, with: MediaAccessError.nonHTTPResponse)
            completionHandler(.cancel)
            return
        }
        // A closed-range request must come back 206. A 200 is only acceptable at offset 0
        // (server returned the whole resource); a 200 at offset>0 means Range was ignored and
        // the body would be the wrong bytes — reject so the caller doesn't corrupt the cache.
        let acceptable = http.statusCode == 206 || (http.statusCode == 200 && startOffset == 0)
        guard acceptable else {
            finish(taskIdentifier: dataTask.taskIdentifier, with: MediaAccessError.httpStatus(http.statusCode))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        guard let state = states[dataTask.taskIdentifier], !state.finished else {
            lock.unlock()
            return
        }
        state.buffer.append(data)
        guard state.buffer.count >= state.minSubBlock else {
            lock.unlock()
            return
        }
        let block = state.buffer
        state.buffer = Data()
        let offset = state.emittedEnd
        state.emittedEnd += Int64(block.count)
        let continuation = state.continuation
        lock.unlock()
        continuation.yield(SubBlock(offset: offset, data: block))
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        guard let state = states[task.taskIdentifier], !state.finished else {
            lock.unlock()
            return
        }
        // Commit-as-you-go: never drop the buffered-but-unemitted tail. Flush it first so a
        // resume starts exactly past what the consumer already received.
        var tail: SubBlock?
        if !state.buffer.isEmpty {
            let block = state.buffer
            state.buffer = Data()
            let offset = state.emittedEnd
            state.emittedEnd += Int64(block.count)
            tail = SubBlock(offset: offset, data: block)
        }
        state.finished = true
        let committed = state.emittedEnd
        let continuation = state.continuation
        states[task.taskIdentifier] = nil
        lock.unlock()

        if let tail { continuation.yield(tail) }

        guard let error else {
            continuation.finish()
            return
        }
        // A deliberate consumer cancel (reanchor/seek) surfaces as NSURLErrorCancelled — end the
        // stream quietly; the consumer is already moving to a new anchor.
        if (error as NSError).code == NSURLErrorCancelled, (error as NSError).domain == NSURLErrorDomain {
            continuation.finish()
            return
        }
        if MediaTransferRetry.isTransient(error) {
            continuation.finish(throwing: ResumableTransferError(lastCommittedOffset: committed, underlying: error))
        } else {
            continuation.finish(throwing: error)
        }
    }

    private func finish(taskIdentifier: Int, with error: Error) {
        lock.lock()
        guard let state = states[taskIdentifier], !state.finished else {
            lock.unlock()
            return
        }
        state.finished = true
        let continuation = state.continuation
        states[taskIdentifier] = nil
        lock.unlock()
        continuation.finish(throwing: error)
    }
}
