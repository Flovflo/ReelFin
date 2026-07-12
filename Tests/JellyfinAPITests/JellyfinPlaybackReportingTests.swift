import Foundation
import JellyfinAPI
import Shared
import XCTest

final class JellyfinPlaybackReportingTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testReportPlaybackStoppedPostsStoppedEndpoint() async throws {
        let recorder = RequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        URLProtocolStub.requestHandler = { request in
            await recorder.record(request)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("{}".utf8)
            )
        }

        let session = URLSession(configuration: configuration)
        let settings = PlaybackReportingSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://example.com")!),
            lastSession: UserSession(userID: "user-1", username: "Flo", token: "token-1")
        )
        let tokenStore = PlaybackReportingTokenStore(storedToken: "token-1")
        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings, session: session)

        try await client.reportPlaybackStopped(
            progress: PlaybackProgressUpdate(
                itemID: "episode-1",
                positionTicks: 123_000_000,
                totalTicks: 456_000_000,
                isPaused: true,
                isPlaying: false,
                didFinish: false,
                playMethod: "DirectPlay"
            )
        )

        let request = await recorder.lastRequest
        XCTAssertEqual(request?.url?.path, "/Sessions/Playing/Stopped")
        XCTAssertEqual(request?.httpMethod, "POST")
    }

    func testFetchPlaybackSourcesUsesCustomBitrateOverrideByDefault() async throws {
        let recorder = RequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        URLProtocolStub.requestHandler = { request in
            await recorder.record(request)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"MediaSources":[]}"#.utf8)
            )
        }

        let session = URLSession(configuration: configuration)
        let settings = PlaybackReportingSettingsStore(
            serverConfiguration: ServerConfiguration(
                serverURL: URL(string: "https://example.com")!,
                preferredQuality: .p480,
                maxStreamingBitrateOverride: 42_000_000
            ),
            lastSession: UserSession(userID: "user-1", username: "Flo", token: "token-1")
        )
        let tokenStore = PlaybackReportingTokenStore(storedToken: "token-1")
        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings, session: session)

        _ = try await client.fetchPlaybackSources(itemID: "movie-1")

        let recordedRequest = await recorder.lastRequest
        let request = try XCTUnwrap(recordedRequest)
        let body = try XCTUnwrap(requestBodyData(from: request))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(request.url?.path, "/Items/movie-1/PlaybackInfo")
        XCTAssertEqual(json["MaxStreamingBitrate"] as? Int, 42_000_000)
        XCTAssertNil(json["DeviceProfile"])
    }

    func testUnauthorizedResponseInvalidatesPersistedSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        URLProtocolStub.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"error":"expired token"}"#.utf8)
            )
        }

        let session = URLSession(configuration: configuration)
        let settings = PlaybackReportingSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://example.com")!),
            lastSession: UserSession(userID: "user-1", username: "Flo", token: "token-1")
        )
        let tokenStore = PlaybackReportingTokenStore(storedToken: "token-1")
        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings, session: session)

        do {
            _ = try await client.fetchPlaybackSources(itemID: "movie-1")
            XCTFail("Expected the expired session to be rejected")
        } catch AppError.unauthenticated {
            // Expected.
        }

        let currentSession = await client.currentSession()
        XCTAssertNil(currentSession)
        XCTAssertNil(settings.lastSession)
        XCTAssertNil(tokenStore.storedToken)
    }

    func testStaleUnauthorizedResponseDoesNotInvalidateNewSession() async throws {
        let gate = StaleUnauthorizedGate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/Users/AuthenticateByName" {
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    Data(#"{"User":{"Id":"user-2","Name":"Flo 2"},"AccessToken":"token-2"}"#.utf8)
                )
            }

            await gate.blockUntilReleased()
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"error":"expired token"}"#.utf8)
            )
        }

        let session = URLSession(configuration: configuration)
        let settings = PlaybackReportingSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://example.com")!),
            lastSession: UserSession(userID: "user-1", username: "Flo", token: "token-1")
        )
        let tokenStore = PlaybackReportingTokenStore(storedToken: "token-1")
        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings, session: session)

        let staleRequest = Task {
            try await client.fetchPlaybackSources(itemID: "movie-1")
        }
        await gate.waitUntilBlocked()

        let replacement = try await client.authenticate(
            credentials: UserCredentials(username: "Flo 2", password: "password")
        )
        await gate.release()

        do {
            _ = try await staleRequest.value
            XCTFail("Expected the stale request to remain unauthorized")
        } catch AppError.unauthenticated {
            // Expected.
        }

        let currentSession = await client.currentSession()
        XCTAssertEqual(currentSession, replacement)
        XCTAssertEqual(settings.lastSession, replacement)
        XCTAssertEqual(tokenStore.storedToken, "token-2")
    }

    func testPublicUnauthorizedResponseDoesNotInvalidateExistingSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        URLProtocolStub.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"error":"invalid credentials"}"#.utf8)
            )
        }

        let original = UserSession(userID: "user-1", username: "Flo", token: "token-1")
        let session = URLSession(configuration: configuration)
        let settings = PlaybackReportingSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://example.com")!),
            lastSession: original
        )
        let tokenStore = PlaybackReportingTokenStore(storedToken: original.token)
        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings, session: session)

        do {
            _ = try await client.authenticate(
                credentials: UserCredentials(username: "Flo", password: "wrong")
            )
            XCTFail("Expected authentication to fail")
        } catch AppError.unauthenticated {
            // Expected.
        }

        let currentSession = await client.currentSession()
        XCTAssertEqual(currentSession, original)
        XCTAssertEqual(settings.lastSession, original)
        XCTAssertEqual(tokenStore.storedToken, original.token)
    }
}

private actor StaleUnauthorizedGate {
    private var isBlocked = false
    private var isReleased = false
    private var blockedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func blockUntilReleased() async {
        isBlocked = true
        blockedContinuation?.resume()
        blockedContinuation = nil

        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilBlocked() async {
        guard !isBlocked else { return }
        await withCheckedContinuation { continuation in
            blockedContinuation = continuation
        }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor RequestRecorder {
    private(set) var lastRequest: URLRequest?

    func record(_ request: URLRequest) {
        lastRequest = request
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    static var requestHandler: (@Sendable (URLRequest) async throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        Task {
            do {
                let (response, data) = try await handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private func requestBodyData(from request: URLRequest) throws -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read < 0 {
            throw try XCTUnwrap(stream.streamError)
        }
        if read == 0 {
            break
        }
        data.append(buffer, count: read)
    }

    return data
}

private final class PlaybackReportingSettingsStore: SettingsStoreProtocol, @unchecked Sendable {
    var serverConfiguration: ServerConfiguration?
    var lastSession: UserSession?
    var episodeReleaseNotificationsEnabled = false
    var hasCompletedOnboarding = false
    var completedOnboardingVersion = 0
    var useCustomPlayerEngine = false

    init(serverConfiguration: ServerConfiguration?, lastSession: UserSession?) {
        self.serverConfiguration = serverConfiguration
        self.lastSession = lastSession
    }
}

private final class PlaybackReportingTokenStore: TokenStoreProtocol, @unchecked Sendable {
    var storedToken: String?

    init(storedToken: String?) {
        self.storedToken = storedToken
    }

    func saveToken(_ token: String) throws {
        storedToken = token
    }

    func fetchToken() throws -> String? {
        storedToken
    }

    func clearToken() throws {
        storedToken = nil
    }
}
