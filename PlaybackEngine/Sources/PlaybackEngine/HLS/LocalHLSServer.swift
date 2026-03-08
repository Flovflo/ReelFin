import Foundation
import Network
import Shared

public struct LocalHLSRequest: Sendable {
    public let method: String
    public let path: String

    public init(method: String, path: String) {
        self.method = method
        self.path = path
    }
}

public struct LocalHLSResponse: Sendable {
    public let statusCode: Int
    public let contentType: String
    public let body: Data

    public init(statusCode: Int, contentType: String, body: Data) {
        self.statusCode = statusCode
        self.contentType = contentType
        self.body = body
    }
}

public enum LocalHLSServerState: Sendable, Equatable {
    case idle
    case starting
    case listening(host: String, port: UInt16)
    case serving(host: String, port: UInt16, requestsServed: Int)
    case failed(reason: String)
    case stopped
}

public protocol LocalHLSServerProtocol: Sendable {
    func start() throws -> URL
    func stop(reason: String)
    func handle(request: LocalHLSRequest) async -> LocalHLSResponse
    func currentState() -> LocalHLSServerState
}

public final class LocalHLSServer: LocalHLSServerProtocol, @unchecked Sendable {
    private static let loopbackHost = "127.0.0.1"
    private static let startupTimeoutSeconds: TimeInterval = 4

    private let session: SyntheticHLSSession
    private let queue = DispatchQueue(label: "com.reelfin.localhls.server")
    private let stateLock = NSLock()

    private var listener: NWListener?
    private var baseURL: URL?
    private var state: LocalHLSServerState = .idle
    private var requestsServed: Int = 0
    private var didLogFirstRequest = false
    private var generation: Int = 0
    private var startupPreflightSnapshotMode = false

    public init(session: SyntheticHLSSession) {
        self.session = session
    }

    public func start() throws -> URL {
        if let baseURL {
            return baseURL
        }

        generation += 1
        requestsServed = 0
        didLogFirstRequest = false
        updateState(.starting)
        AppLog.nativeBridge.notice("[NB-DIAG] hls.server.start.requested — generation=\(self.generation, privacy: .public) bind=\(Self.loopbackHost, privacy: .public):0")

        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        let startupLock = NSLock()
        let startupSignal = DispatchSemaphore(value: 0)
        var startupCompleted = false
        var startupURL: URL?
        var startupError: Error?

        func finishStartup(url: URL?, error: Error?) {
            startupLock.lock()
            defer { startupLock.unlock() }
            guard !startupCompleted else { return }
            startupCompleted = true
            startupURL = url
            startupError = error
            startupSignal.signal()
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener else { return }
            switch state {
            case .ready:
                let port = listener.port?.rawValue ?? 0
                guard port > 0 else {
                    let error = NSError(
                        domain: "LocalHLSServer",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Listener reached ready state without a usable port."]
                    )
                    self.updateState(.failed(reason: "ready_without_port"))
                    AppLog.nativeBridge.error("[NB-DIAG] hls.server.start.failed — generation=\(self.generation, privacy: .public) reason=ready_without_port")
                    finishStartup(url: nil, error: error)
                    return
                }

                let url = URL(string: "http://\(Self.loopbackHost):\(port)/")!
                self.baseURL = url
                self.updateState(.listening(host: Self.loopbackHost, port: port))
                AppLog.nativeBridge.notice("[NB-DIAG] hls.server.ready — generation=\(self.generation, privacy: .public) bound=\(Self.loopbackHost, privacy: .public):\(port, privacy: .public)")
                finishStartup(url: url, error: nil)

            case .failed(let error):
                self.updateState(.failed(reason: error.localizedDescription))
                AppLog.nativeBridge.error("[NB-DIAG] hls.server.start.failed — generation=\(self.generation, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                finishStartup(url: nil, error: error)

            case .cancelled:
                let error = NSError(
                    domain: "LocalHLSServer",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Listener cancelled before startup completed."]
                )
                self.updateState(.stopped)
                finishStartup(url: nil, error: error)

            default:
                break
            }
        }
        listener.start(queue: queue)

        let waitResult = startupSignal.wait(timeout: .now() + Self.startupTimeoutSeconds)
        if waitResult == .timedOut {
            listener.cancel()
            self.listener = nil
            self.baseURL = nil
            updateState(.failed(reason: "startup_timeout"))
            AppLog.nativeBridge.error("[NB-DIAG] hls.server.start.failed — generation=\(self.generation, privacy: .public) reason=startup_timeout")
            throw NSError(
                domain: "LocalHLSServer",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Timed out while waiting for local HLS listener readiness."]
            )
        }

        if let startupError {
            listener.cancel()
            self.listener = nil
            self.baseURL = nil
            throw startupError
        }
        guard let startupURL, startupURL.port ?? 0 > 0 else {
            listener.cancel()
            self.listener = nil
            self.baseURL = nil
            updateState(.failed(reason: "invalid_startup_url"))
            throw NSError(
                domain: "LocalHLSServer",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Local HLS startup produced invalid URL."]
            )
        }

        return startupURL
    }

    public func stop(reason: String = "unspecified") {
        AppLog.nativeBridge.notice("[NB-DIAG] hls.server.stop — generation=\(self.generation, privacy: .public) reason=\(reason, privacy: .public)")
        listener?.cancel()
        listener = nil
        baseURL = nil
        updateState(.stopped)
    }

    public func currentState() -> LocalHLSServerState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state
    }

    public func setStartupPreflightSnapshotMode(_ enabled: Bool) {
        stateLock.lock()
        startupPreflightSnapshotMode = enabled
        stateLock.unlock()
        AppLog.nativeBridge.notice(
            "[NB-DIAG] hls.server.snapshot-mode — generation=\(self.generation, privacy: .public) enabled=\(enabled, privacy: .public)"
        )
    }

    public func handle(request: LocalHLSRequest) async -> LocalHLSResponse {
        let method = request.method.uppercased()
        guard method == "GET" || method == "HEAD" else {
            return LocalHLSResponse(statusCode: 405, contentType: "text/plain", body: Data("Method Not Allowed".utf8))
        }

        do {
            let wantsBody = (method == "GET")

            switch request.path {
            case "/", "/master.m3u8":
                let playlist = try await session.masterPlaylist(baseURL: baseURL)
                let body = wantsBody ? Data(playlist.utf8) : Data()
                return LocalHLSResponse(statusCode: 200, contentType: "application/vnd.apple.mpegurl", body: body)
            case "/video.m3u8":
                let snapshotMode = currentStartupPreflightSnapshotMode()
                let playlist = try await session.mediaPlaylist(
                    baseURL: baseURL,
                    startupPreflightSnapshot: snapshotMode
                )
                let body = wantsBody ? Data(playlist.utf8) : Data()
                return LocalHLSResponse(statusCode: 200, contentType: "application/vnd.apple.mpegurl", body: body)
            case "/init.mp4":
                let data = try await session.initSegment()
                let body = wantsBody ? data : Data()
                return LocalHLSResponse(statusCode: 200, contentType: "video/mp4", body: body)
            default:
                if request.path.hasPrefix("/segment_"), request.path.hasSuffix(".m4s") {
                    let sequenceString = request.path
                        .replacingOccurrences(of: "/segment_", with: "")
                        .replacingOccurrences(of: ".m4s", with: "")
                    let sequence = Int(sequenceString) ?? 0
                    let data = try await session.segment(sequence: sequence)
                    let body = wantsBody ? data : Data()
                    // fMP4 segments use video/iso.segment MIME type per CMAF spec
                    return LocalHLSResponse(statusCode: 200, contentType: "video/iso.segment", body: body)
                }
                return LocalHLSResponse(statusCode: 404, contentType: "text/plain", body: Data("Not Found".utf8))
            }
        } catch {
            return LocalHLSResponse(
                statusCode: 500,
                contentType: "text/plain",
                body: Data("Internal Server Error: \(error.localizedDescription)".utf8)
            )
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            let request = Self.parseRequest(data)
            self.recordIncomingRequest(path: request.path, method: request.method)
            Task {
                let response = await self.handle(request: request)
                self.recordServedResponse(path: request.path, status: response.statusCode, bytes: response.body.count)
                let payload = Self.serialize(response: response)
                connection.send(content: payload, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private static func parseRequest(_ data: Data?) -> LocalHLSRequest {
        guard
            let data,
            let text = String(data: data, encoding: .utf8),
            let firstLine = text.split(separator: "\n").first
        else {
            return LocalHLSRequest(method: "GET", path: "/master.m3u8")
        }

        let tokens = firstLine.split(separator: " ")
        guard tokens.count >= 2 else {
            return LocalHLSRequest(method: "GET", path: "/master.m3u8")
        }

        let rawPath = String(tokens[1])
        let path: String
        if let url = URL(string: rawPath), let absolutePath = url.path.isEmpty ? nil : url.path {
            path = absolutePath
        } else if let components = URLComponents(string: rawPath), let componentPath = components.path.isEmpty ? nil : components.path {
            path = componentPath
        } else {
            path = rawPath
        }

        return LocalHLSRequest(method: String(tokens[0]), path: path)
    }

    private static func serialize(response: LocalHLSResponse) -> Data {
        var headers = "HTTP/1.1 \(response.statusCode) \(reasonPhrase(for: response.statusCode))\r\n"
        headers += "Content-Type: \(response.contentType)\r\n"
        headers += "Content-Length: \(response.body.count)\r\n"
        headers += "Cache-Control: no-cache\r\n"
        headers += "Access-Control-Allow-Origin: *\r\n"
        headers += "Connection: close\r\n"
        headers += "\r\n"

        var payload = Data(headers.utf8)
        payload.append(response.body)
        return payload
    }

    private static func reasonPhrase(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default: return "Status"
        }
    }

    private func updateState(_ newState: LocalHLSServerState) {
        stateLock.lock()
        state = newState
        stateLock.unlock()
    }

    private func recordIncomingRequest(path: String, method: String) {
        stateLock.lock()
        requestsServed += 1
        let count = requestsServed
        let current = state
        let shouldLogFirstRequest = !didLogFirstRequest
        if shouldLogFirstRequest {
            didLogFirstRequest = true
        }

        if let url = baseURL, let port = url.port {
            state = .serving(host: Self.loopbackHost, port: UInt16(port), requestsServed: count)
        } else if case .listening(let host, let port) = current {
            state = .serving(host: host, port: port, requestsServed: count)
        }
        stateLock.unlock()

        if shouldLogFirstRequest {
            AppLog.nativeBridge.notice("[NB-DIAG] hls.server.first-request — generation=\(self.generation, privacy: .public) method=\(method, privacy: .public) path=\(path, privacy: .public)")
        }
    }

    private func recordServedResponse(path: String, status: Int, bytes: Int) {
        AppLog.nativeBridge.notice("[NB-DIAG] hls.server.route — generation=\(self.generation, privacy: .public) path=\(path, privacy: .public) status=\(status, privacy: .public) bytes=\(bytes, privacy: .public)")
    }

    private func currentStartupPreflightSnapshotMode() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return startupPreflightSnapshotMode
    }
}
