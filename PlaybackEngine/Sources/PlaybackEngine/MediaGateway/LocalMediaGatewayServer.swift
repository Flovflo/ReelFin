import Foundation
import NativeMediaCore
import Network
import Shared

public final class LocalMediaGatewayServer: @unchecked Sendable {
    public typealias RequestObserver = (_ method: String, _ rangeDescription: String) -> Void

    private let session: LocalMediaGatewaySession
    private let requestObserver: RequestObserver?
    private let queue = DispatchQueue(label: "reelfin.local-media-gateway")
    private var listener: NWListener?

    public init(session: LocalMediaGatewaySession, requestObserver: RequestObserver? = nil) {
        self.session = session
        self.requestObserver = requestObserver
    }

    public func start() throws -> URL {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        var startError: Error?
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case .failed(let error):
                startError = error
                ready.signal()
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 4)
        if let startError { throw startError }
        guard let port = listener.port else { throw MediaAccessError.cannotDetermineSize }
        let baseURL = URL(string: "http://127.0.0.1:\(port.rawValue)")!
        return session.localAssetURL(baseURL: baseURL)
    }

    public func stop(reason: String) {
        listener?.cancel()
        listener = nil
        Task { await session.cancel() }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self] data, _, _, _ in
            guard let self, let data else {
                connection.cancel()
                return
            }
            self.respond(to: data, connection: connection)
        }
    }

    private func respond(to data: Data, connection: NWConnection) {
        guard let request = LocalMediaGatewayHTTPRequest(data) else {
            send(LocalMediaGatewayHTTPResponse.badRequest(), connection: connection)
            return
        }
        Task {
            if await streamResponseIfNeeded(for: request, connection: connection) {
                return
            }
            let response = await makeResponse(for: request)
            send(response, connection: connection)
        }
    }

    private func streamResponseIfNeeded(
        for request: LocalMediaGatewayHTTPRequest,
        connection: NWConnection
    ) async -> Bool {
        guard session.acceptsLocalPath(request.path),
              request.method == "GET" else {
            return false
        }
        var didSendHeaders = false
        do {
            guard let response = try await session.streamingResponse(for: request.range) else {
                return false
            }
            requestObserver?(request.method, String(describing: request.range))
            let headers = LocalMediaGatewayHTTPResponse.partialHeaders(
                range: response.range,
                totalLength: response.totalLength,
                contentType: response.contentType
            )
            try await sendPart(headers, connection: connection)
            didSendHeaders = true
            for try await chunk in response.chunks {
                try await sendPart(chunk, connection: connection)
            }
        } catch {
            if didSendHeaders {
                AppLog.playback.debug(
                    "playback.cache.gateway.stream_failed_after_headers — error=\(String(describing: error), privacy: .public)"
                )
            } else {
                await sendStreamingFailure(error, connection: connection)
            }
        }
        connection.cancel()
        return true
    }

    private func makeResponse(for request: LocalMediaGatewayHTTPRequest) async -> Data {
        guard session.acceptsLocalPath(request.path) else {
            return LocalMediaGatewayHTTPResponse.notFound()
        }
        requestObserver?(request.method, String(describing: request.range))
        do {
            if request.method == "HEAD" {
                return LocalMediaGatewayHTTPResponse.head(
                    totalLength: try await session.size(),
                    contentType: try await session.contentType()
                )
            }
            guard request.method == "GET" else {
                return LocalMediaGatewayHTTPResponse.badRequest()
            }
            let result = try await session.response(for: request.range)
            return LocalMediaGatewayHTTPResponse.partial(
                data: result.data,
                range: result.range,
                totalLength: result.totalLength,
                contentType: result.contentType
            )
        } catch {
            if let mediaError = error as? MediaAccessError, case .invalidRange = mediaError {
                return LocalMediaGatewayHTTPResponse.rangeNotSatisfiable(totalLength: try? await session.size())
            }
            AppLog.playback.debug(
                "playback.cache.gateway.response_failed — request=\(request.method, privacy: .public) range=\(String(describing: request.range), privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            return LocalMediaGatewayHTTPResponse.serverError()
        }
    }

    private func send(_ data: Data, connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendPart(_ data: Data, connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func sendStreamingFailure(_ error: Error, connection: NWConnection) async {
        if let mediaError = error as? MediaAccessError, case .invalidRange = mediaError {
            send(LocalMediaGatewayHTTPResponse.rangeNotSatisfiable(totalLength: try? await session.size()), connection: connection)
            return
        }
        AppLog.playback.debug(
            "playback.cache.gateway.stream_failed — error=\(String(describing: error), privacy: .public)"
        )
        send(LocalMediaGatewayHTTPResponse.serverError(), connection: connection)
    }
}
