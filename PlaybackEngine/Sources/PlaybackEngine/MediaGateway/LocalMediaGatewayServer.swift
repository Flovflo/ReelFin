import Foundation
import NativeMediaCore
import Network

public final class LocalMediaGatewayServer: @unchecked Sendable {
    private let session: LocalMediaGatewaySession
    private let queue = DispatchQueue(label: "reelfin.local-media-gateway")
    private var listener: NWListener?

    public init(session: LocalMediaGatewaySession) {
        self.session = session
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
        return URL(string: "http://127.0.0.1:\(port.rawValue)/media/\(session.id)")!
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
            let response = await makeResponse(for: request)
            send(response, connection: connection)
        }
    }

    private func makeResponse(for request: LocalMediaGatewayHTTPRequest) async -> Data {
        guard request.path == "/media/\(session.id)" else {
            return LocalMediaGatewayHTTPResponse.notFound()
        }
        do {
            if request.method == "HEAD" {
                return LocalMediaGatewayHTTPResponse.head(totalLength: try await session.size())
            }
            guard request.method == "GET", let range = request.range else {
                return LocalMediaGatewayHTTPResponse.badRequest()
            }
            let result = try await session.response(for: range)
            return LocalMediaGatewayHTTPResponse.partial(
                data: result.data,
                range: range,
                totalLength: result.totalLength
            )
        } catch {
            return LocalMediaGatewayHTTPResponse.serverError()
        }
    }

    private func send(_ data: Data, connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
