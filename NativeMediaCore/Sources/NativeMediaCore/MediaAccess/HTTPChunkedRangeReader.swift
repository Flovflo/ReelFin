import Foundation

/// Reads an HTTP range response in OS-sized `Data` chunks instead of byte-by-byte.
///
/// `URLSession.AsyncBytes` iteration (`for try await byte in bytes { data.append(byte) }`)
/// is CPU-bound: every byte is an `await` suspension plus a single-byte `Data.append`.
/// Measured against a real 26 Mbps direct-play stream it tops out around 7-10 MB/s on a
/// fast Mac (and far less on device), which is below the sustained rate a high-bitrate
/// movie needs — so the player buffer drains and playback cuts to rebuffer. Routing all
/// media reads through this delegate-driven chunk reader restores full bandwidth (bulk
/// `data(for:)` measured ~40 MB/s on the same stream) and also bounds memory: it stops
/// and cancels the transfer as soon as `maxLength` bytes have been collected, so an
/// unexpected `200` (server ignoring `Range`) can never pull a whole multi-GB file.
public final class HTTPChunkedRangeReader: NSObject, @unchecked Sendable {
    private let maxLength: Int
    private let lock = NSLock()
    private var buffer = Data()
    private var httpResponse: HTTPURLResponse?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var pendingResult: Result<(Data, HTTPURLResponse), Error>?
    private var finished = false

    private init(maxLength: Int) {
        self.maxLength = max(0, maxLength)
        super.init()
    }

    /// Performs `request` and returns up to `maxLength` bytes of the body together with the
    /// HTTP response. The transfer is cancelled the moment `maxLength` is reached.
    public static func collect(
        request: URLRequest,
        configuration: URLSessionConfiguration,
        maxLength: Int
    ) async throws -> (Data, HTTPURLResponse) {
        let reader = HTTPChunkedRangeReader(maxLength: maxLength)
        return try await reader.start(request: request, configuration: configuration)
    }

    private func start(
        request: URLRequest,
        configuration: URLSessionConfiguration
    ) async throws -> (Data, HTTPURLResponse) {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        // Create the task before installing the cancellation handler. If the surrounding
        // Task is already cancelled, `onCancel` runs immediately; cancelling the data task
        // (rather than invalidating the session) avoids "task created in a session that has
        // been invalidated" when the producer is cancelled — which happens routinely during
        // playback as AVPlayer closes connections once its buffer is full.
        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                // The transfer may already have completed/cancelled before we installed the
                // continuation (e.g. onCancel cancelled the task before it was resumed).
                if let pending = pendingResult {
                    finished = true
                    lock.unlock()
                    continuation.resume(with: pending)
                    return
                }
                if finished {
                    lock.unlock()
                    continuation.resume(throwing: MediaAccessError.cancelled)
                    return
                }
                self.continuation = continuation
                self.buffer.reserveCapacity(min(maxLength, 8 * 1_024 * 1_024))
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        if let continuation {
            finished = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            // Result arrived before the continuation was installed; stash it so the
            // continuation can deliver it immediately once set.
            pendingResult = result
            lock.unlock()
        }
    }
}

extension HTTPChunkedRangeReader: URLSessionDataDelegate {
    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            lock.lock()
            httpResponse = http
            lock.unlock()
        }
        completionHandler(.allow)
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        let remaining = maxLength - buffer.count
        if remaining <= 0 {
            lock.unlock()
            dataTask.cancel()
            return
        }
        if data.count <= remaining {
            buffer.append(data)
        } else {
            buffer.append(data.prefix(remaining))
        }
        let reachedMax = buffer.count >= maxLength
        let http = httpResponse
        let collected = reachedMax ? buffer : Data()
        lock.unlock()

        if reachedMax {
            dataTask.cancel()
            if let http {
                finish(.success((collected, http)))
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let http = httpResponse
        let collected = buffer
        lock.unlock()

        if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            // Cancelled because we already reached maxLength; the success was (or is now) delivered.
            if let http {
                finish(.success((collected, http)))
            } else {
                finish(.failure(MediaAccessError.cancelled))
            }
            return
        }
        if let error {
            finish(.failure(error))
            return
        }
        if let http {
            finish(.success((collected, http)))
        } else {
            finish(.failure(MediaAccessError.nonHTTPResponse))
        }
    }
}
