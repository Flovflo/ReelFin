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
    public let headers: [String: String]

    public init(statusCode: Int, contentType: String, body: Data, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.contentType = contentType
        self.body = body
        self.headers = headers
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
    private let connectionCallbackQueue = DispatchQueue(
        label: "com.reelfin.localhls.server.connection-callback",
        attributes: .concurrent
    )
    private let stateLock = NSLock()
    private let connectionGate: LocalPlaybackConnectionGate
    private let connectionCallbackHook: (@Sendable () -> Void)?

    private var listener: NWListener?
    private var baseURL: URL?
    private var security: LocalPlaybackServerSecurity?
    private var requiredLocalEndpoint: NWEndpoint?
    private var state: LocalHLSServerState = .idle
    private var requestsServed: Int = 0
    private var didLogFirstRequest = false
    private var generation: Int = 0
    private var acceptingConnections = false
    private var receiveStartCount = 0
    private var startupPreflightSnapshotMode = false
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
    private var connectionTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var connectionLeases: [ObjectIdentifier: LocalPlaybackConnectionGate.Lease] = [:]

    public convenience init(session: SyntheticHLSSession) {
        self.init(
            session: session,
            connectionCapacity: LocalPlaybackServerSecurity.defaultConnectionCapacity
        )
    }

    init(
        session: SyntheticHLSSession,
        connectionCapacity: Int?,
        connectionGate: LocalPlaybackConnectionGate? = nil,
        connectionCallbackHook: (@Sendable () -> Void)? = nil
    ) {
        self.session = session
        self.connectionGate = connectionGate ?? LocalPlaybackConnectionGate(capacity: connectionCapacity)
        self.connectionCallbackHook = connectionCallbackHook
    }

    public func start() throws -> URL {
        if let existingURL = stateLock.withLock({ baseURL }) {
            return existingURL
        }

        let security = LocalPlaybackServerSecurity()
        let configuredListener = try LocalPlaybackServerSecurity.makeLoopbackListener()
        let listener = configuredListener.listener
        let startedGeneration = stateLock.withLock { () -> Int in
            generation += 1
            acceptingConnections = true
            receiveStartCount = 0
            requestsServed = 0
            didLogFirstRequest = false
            state = .starting
            self.listener = listener
            self.security = security
            requiredLocalEndpoint = configuredListener.requiredLocalEndpoint
            return generation
        }
        AppLog.nativeBridge.notice("[NB-DIAG] hls.server.start.requested — generation=\(startedGeneration, privacy: .public) bind=\(Self.loopbackHost, privacy: .public):0")

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
            guard let self else {
                connection.cancel()
                return
            }
            self.connectionCallbackQueue.async { [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }
                self.connectionCallbackHook?()
                self.handle(connection: connection, generation: startedGeneration)
            }
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
                    self.updateState(.failed(reason: "ready_without_port"), generation: startedGeneration)
                    AppLog.nativeBridge.error("[NB-DIAG] hls.server.start.failed — generation=\(startedGeneration, privacy: .public) reason=ready_without_port")
                    finishStartup(url: nil, error: error)
                    return
                }

                guard let listenerPort = NWEndpoint.Port(rawValue: port),
                      let url = security.baseURL(port: listenerPort) else {
                    let error = NSError(
                        domain: "LocalHLSServer",
                        code: 6,
                        userInfo: [NSLocalizedDescriptionKey: "Listener produced an invalid capability URL."]
                    )
                    self.updateState(.failed(reason: "invalid_capability_url"), generation: startedGeneration)
                    finishStartup(url: nil, error: error)
                    return
                }
                let acceptedReady = self.stateLock.withLock { () -> Bool in
                    guard self.acceptingConnections,
                          self.generation == startedGeneration,
                          self.listener === listener else { return false }
                    self.baseURL = url
                    self.state = .listening(host: Self.loopbackHost, port: port)
                    return true
                }
                guard acceptedReady else {
                    listener.cancel()
                    finishStartup(url: nil, error: CancellationError())
                    return
                }
                AppLog.nativeBridge.notice("[NB-DIAG] hls.server.ready — generation=\(startedGeneration, privacy: .public) bound=\(Self.loopbackHost, privacy: .public):\(port, privacy: .public)")
                finishStartup(url: url, error: nil)

            case .failed(let error):
                self.updateState(.failed(reason: error.localizedDescription), generation: startedGeneration)
                AppLog.nativeBridge.error("[NB-DIAG] hls.server.start.failed — generation=\(startedGeneration, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                finishStartup(url: nil, error: error)

            case .cancelled:
                let error = NSError(
                    domain: "LocalHLSServer",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Listener cancelled before startup completed."]
                )
                self.updateState(.stopped, generation: startedGeneration)
                finishStartup(url: nil, error: error)

            default:
                break
            }
        }
        listener.start(queue: queue)

        let waitResult = startupSignal.wait(timeout: .now() + Self.startupTimeoutSeconds)
        if waitResult == .timedOut {
            listener.cancel()
            clearStartup(generation: startedGeneration, state: .failed(reason: "startup_timeout"))
            AppLog.nativeBridge.error("[NB-DIAG] hls.server.start.failed — generation=\(startedGeneration, privacy: .public) reason=startup_timeout")
            throw NSError(
                domain: "LocalHLSServer",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Timed out while waiting for local HLS listener readiness."]
            )
        }

        if let startupError {
            listener.cancel()
            clearStartup(generation: startedGeneration, state: .failed(reason: startupError.localizedDescription))
            throw startupError
        }
        guard let startupURL, startupURL.port ?? 0 > 0 else {
            listener.cancel()
            clearStartup(generation: startedGeneration, state: .failed(reason: "invalid_startup_url"))
            throw NSError(
                domain: "LocalHLSServer",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Local HLS startup produced invalid URL."]
            )
        }

        return startupURL
    }

    public func stop(reason: String = "unspecified") {
        let drained = stateLock.withLock { () -> (Int, NWListener?, [NWConnection], [Task<Void, Never>], [LocalPlaybackConnectionGate.Lease]) in
            acceptingConnections = false
            let result = (
                generation,
                listener,
                Array(activeConnections.values),
                Array(connectionTasks.values),
                Array(connectionLeases.values)
            )
            listener = nil
            baseURL = nil
            security = nil
            requiredLocalEndpoint = nil
            activeConnections.removeAll()
            connectionTasks.removeAll()
            connectionLeases.removeAll()
            state = .stopped
            return result
        }
        AppLog.nativeBridge.notice("[NB-DIAG] hls.server.stop — generation=\(drained.0, privacy: .public) reason=\(reason, privacy: .public)")
        drained.1?.cancel()
        drained.2.forEach { $0.cancel() }
        drained.3.forEach { $0.cancel() }
        drained.4.forEach { $0.release() }
    }

    deinit {
        let transport = stateLock.withLock { () -> (NWListener?, [NWConnection], [Task<Void, Never>], [LocalPlaybackConnectionGate.Lease]) in
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
        transport.0?.cancel()
        transport.1.forEach { $0.cancel() }
        transport.2.forEach { $0.cancel() }
        transport.3.forEach { $0.release() }
    }

    public func currentState() -> LocalHLSServerState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state
    }

    public func setStartupPreflightSnapshotMode(_ enabled: Bool) {
        let currentGeneration = stateLock.withLock { () -> Int in
            startupPreflightSnapshotMode = enabled
            return generation
        }
        AppLog.nativeBridge.notice(
            "[NB-DIAG] hls.server.snapshot-mode — generation=\(currentGeneration, privacy: .public) enabled=\(enabled, privacy: .public)"
        )
    }

    public func handle(request: LocalHLSRequest) async -> LocalHLSResponse {
        guard let context = stateLock.withLock({ () -> (Int, LocalPlaybackServerSecurity, URL?)? in
            guard acceptingConnections, let security else { return nil }
            return (generation, security, baseURL)
        }) else {
            return LocalHLSResponse(statusCode: 404, contentType: "text/plain", body: Data("Not Found".utf8))
        }
        return await handle(request: request, generation: context.0, security: context.1, baseURL: context.2)
    }

    private func handle(
        request: LocalHLSRequest,
        generation expectedGeneration: Int,
        security: LocalPlaybackServerSecurity,
        baseURL: URL?
    ) async -> LocalHLSResponse {
        let method = request.method.uppercased()
        guard method == "GET" || method == "HEAD" else {
            return LocalHLSResponse(statusCode: 405, contentType: "text/plain", body: Data("Method Not Allowed".utf8))
        }

        guard stateLock.withLock({ acceptingConnections && generation == expectedGeneration }),
              let resourcePath = security.authorizedResourcePath(for: request.path) else {
            return LocalHLSResponse(statusCode: 404, contentType: "text/plain", body: Data("Not Found".utf8))
        }

        do {
            let wantsBody = (method == "GET")

            switch resourcePath {
            case "/master.m3u8":
                let playlist = try await session.masterPlaylist(baseURL: baseURL)
                let body = wantsBody ? Data(playlist.utf8) : Data()
                return LocalHLSResponse(
                    statusCode: 200,
                    contentType: "application/vnd.apple.mpegurl",
                    body: body,
                    headers: ["Cache-Control": "public, max-age=300, immutable"]
                )
            case "/video.m3u8":
                let snapshotMode = stateLock.withLock {
                    acceptingConnections && generation == expectedGeneration && startupPreflightSnapshotMode
                }
                let playlist = try await session.mediaPlaylist(
                    baseURL: baseURL,
                    startupPreflightSnapshot: snapshotMode
                )
                let body = wantsBody ? Data(playlist.utf8) : Data()
                return LocalHLSResponse(
                    statusCode: 200,
                    contentType: "application/vnd.apple.mpegurl",
                    body: body,
                    headers: ["Cache-Control": "no-cache"]
                )
            case "/init.mp4":
                let data = try await session.initSegment()
                let body = wantsBody ? data : Data()
                return LocalHLSResponse(
                    statusCode: 200,
                    contentType: "video/mp4",
                    body: body,
                    headers: ["Cache-Control": "public, max-age=31536000, immutable"]
                )
            default:
                if let sequence = LocalPlaybackServerSecurity.canonicalSegmentSequence(forResourcePath: resourcePath) {
                    let data = try await session.segment(sequence: sequence)
                    let body = wantsBody ? data : Data()
                    // fMP4 segments use video/iso.segment MIME type per CMAF spec
                    return LocalHLSResponse(
                        statusCode: 200,
                        contentType: "video/iso.segment",
                        body: body,
                        headers: ["Cache-Control": "public, max-age=31536000, immutable"]
                    )
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

    private func handle(connection: NWConnection, generation expectedGeneration: Int) {
        let cid = ObjectIdentifier(connection)
        let admitted = stateLock.withLock { () -> Bool in
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
                guard self?.beginReceive(id: cid, generation: expectedGeneration) == true else { return }
                let data = await Self.receiveRequestData(over: connection)
                guard !Task.isCancelled, let self,
                      let context = self.requestContext(generation: expectedGeneration) else { return }
                let request = Self.parseRequest(data)
                let routeClass = context.security.routeClass(for: request.path)
                self.recordIncomingRequest(
                    routeClass: routeClass,
                    method: request.method,
                    generation: expectedGeneration
                )
                let response = await self.handle(
                    request: request,
                    generation: expectedGeneration,
                    security: context.security,
                    baseURL: context.baseURL
                )
                guard !Task.isCancelled,
                      self.isCurrent(generation: expectedGeneration) else { return }
                self.recordServedResponse(
                    routeClass: routeClass,
                    status: response.statusCode,
                    bytes: response.body.count,
                    generation: expectedGeneration
                )
                let payload = Self.serialize(response: response)
                await withCheckedContinuation { continuation in
                    connection.send(content: payload, completion: .contentProcessed { _ in continuation.resume() })
                }
            }
            connectionTasks[cid] = task
            return true
        }
        if !admitted {
            connection.cancel()
        }
    }

    private static func receiveRequestData(over connection: NWConnection) async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                continuation.resume(returning: data)
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
        path = rawPath

        return LocalHLSRequest(method: String(tokens[0]), path: path)
    }

    private static func serialize(response: LocalHLSResponse) -> Data {
        var headers = "HTTP/1.1 \(response.statusCode) \(reasonPhrase(for: response.statusCode))\r\n"
        headers += "Content-Type: \(response.contentType)\r\n"
        headers += "Content-Length: \(response.body.count)\r\n"
        headers += "Cache-Control: \(response.headers["Cache-Control"] ?? "no-cache")\r\n"
        for (name, value) in response.headers.sorted(by: { $0.key < $1.key }) where name.lowercased() != "cache-control" {
            headers += "\(name): \(value)\r\n"
        }
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

    private func updateState(_ newState: LocalHLSServerState, generation expectedGeneration: Int) {
        stateLock.withLock {
            guard generation == expectedGeneration else { return }
            state = newState
        }
    }

    private func clearStartup(generation expectedGeneration: Int, state newState: LocalHLSServerState) {
        stateLock.withLock {
            guard generation == expectedGeneration else { return }
            acceptingConnections = false
            listener = nil
            baseURL = nil
            security = nil
            requiredLocalEndpoint = nil
            state = newState
        }
    }

    private func recordIncomingRequest(
        routeClass: LocalPlaybackServerSecurity.RouteClass,
        method: String,
        generation expectedGeneration: Int
    ) {
        stateLock.lock()
        guard acceptingConnections, generation == expectedGeneration else {
            stateLock.unlock()
            return
        }
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
            AppLog.nativeBridge.notice("[NB-DIAG] hls.server.first-request — generation=\(expectedGeneration, privacy: .public) method=\(method, privacy: .public) route=\(routeClass.rawValue, privacy: .public)")
        }
    }

    private func recordServedResponse(
        routeClass: LocalPlaybackServerSecurity.RouteClass,
        status: Int,
        bytes: Int,
        generation expectedGeneration: Int
    ) {
        AppLog.nativeBridge.notice("[NB-DIAG] hls.server.route — generation=\(expectedGeneration, privacy: .public) route=\(routeClass.rawValue, privacy: .public) status=\(status, privacy: .public) bytes=\(bytes, privacy: .public)")
    }

    private func currentStartupPreflightSnapshotMode() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return startupPreflightSnapshotMode
    }

    private func requestContext(
        generation expectedGeneration: Int
    ) -> (security: LocalPlaybackServerSecurity, baseURL: URL?)? {
        stateLock.withLock {
            guard acceptingConnections, generation == expectedGeneration, let security else { return nil }
            return (security, baseURL)
        }
    }

    private func isCurrent(generation expectedGeneration: Int) -> Bool {
        stateLock.withLock { acceptingConnections && generation == expectedGeneration }
    }

    private func beginReceive(id: ObjectIdentifier, generation expectedGeneration: Int) -> Bool {
        stateLock.withLock {
            guard acceptingConnections,
                  generation == expectedGeneration,
                  activeConnections[id] != nil,
                  connectionTasks[id] != nil else { return false }
            receiveStartCount += 1
            return true
        }
    }

    private func finishConnection(
        id: ObjectIdentifier,
        connection: NWConnection
    ) {
        connection.cancel()
        let lease = stateLock.withLock { () -> LocalPlaybackConnectionGate.Lease? in
            activeConnections[id] = nil
            connectionTasks[id] = nil
            return connectionLeases.removeValue(forKey: id)
        }
        lease?.release()
    }

#if DEBUG
    var debugRequiredLocalEndpoint: NWEndpoint? { stateLock.withLock { requiredLocalEndpoint } }
    var debugConnectionSnapshot: LocalPlaybackConnectionGate.Snapshot { connectionGate.snapshot }
    var debugActiveConnectionCount: Int { stateLock.withLock { activeConnections.count } }
    var debugConnectionTaskCount: Int { stateLock.withLock { connectionTasks.count } }
    var debugReceiveStartCount: Int { stateLock.withLock { receiveStartCount } }
#endif
}
