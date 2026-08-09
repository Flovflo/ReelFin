import Foundation
import JellyfinAPI
import Shared
import XCTest

final class JellyfinQuickConnectOriginTests: XCTestCase {
    override func tearDown() {
        QuickConnectURLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testPollAndExchangeUseOriginThatIssuedSecret() async throws {
        let recorder = QuickConnectRequestRecorder()
        let fixture = makeQuickConnectFixture(
            persistedServerURL: URL(string: "https://a.example/old")!,
            recorder: recorder
        )
        let issuingServerURL = URL(string: "https://b.example/jellyfin")!

        let state = try await fixture.client.initiateQuickConnect(serverURL: issuingServerURL)
        _ = try await fixture.client.pollQuickConnect(secret: state.secret)

        let destinations = await recorder.destinations
        XCTAssertEqual(
            destinations,
            [
                QuickConnectRequestDestination(host: "b.example", path: "/jellyfin/QuickConnect/Initiate"),
                QuickConnectRequestDestination(host: "b.example", path: "/jellyfin/QuickConnect/Connect"),
                QuickConnectRequestDestination(host: "b.example", path: "/jellyfin/Users/AuthenticateWithQuickConnect")
            ]
        )
    }

    func testInitiationDoesNotReplacePersistedAuthenticationState() async throws {
        let oldServerURL = URL(string: "https://a.example/old")!
        let oldSession = UserSession(userID: "user-a", username: "User A", token: "token-a")
        let fixture = makeQuickConnectFixture(
            persistedServerURL: oldServerURL,
            persistedSession: oldSession,
            persistedToken: oldSession.token,
            recorder: QuickConnectRequestRecorder()
        )

        _ = try await fixture.client.initiateQuickConnect(
            serverURL: URL(string: "https://b.example/jellyfin")!
        )

        let currentConfiguration = await fixture.client.currentConfiguration()
        let currentSession = await fixture.client.currentSession()
        XCTAssertEqual(currentConfiguration?.serverURL, oldServerURL)
        XCTAssertEqual(currentSession, oldSession)
        XCTAssertEqual(fixture.settings.serverConfiguration?.serverURL, oldServerURL)
        XCTAssertEqual(fixture.settings.lastSession, oldSession)
        XCTAssertEqual(fixture.tokenStore.storedToken, oldSession.token)
    }

    func testSuccessfulExchangePersistsIssuingOriginSessionAndToken() async throws {
        let recorder = QuickConnectRequestRecorder()
        let fixture = makeQuickConnectFixture(
            persistedServerURL: URL(string: "https://a.example/old")!,
            persistedSession: UserSession(userID: "user-a", username: "User A", token: "token-a"),
            persistedToken: "token-a",
            recorder: recorder
        )
        let issuingServerURL = URL(string: "https://b.example/jellyfin")!

        let state = try await fixture.client.initiateQuickConnect(serverURL: issuingServerURL)
        let polledSession = try await fixture.client.pollQuickConnect(secret: state.secret)
        let session = try XCTUnwrap(polledSession)

        let currentConfiguration = await fixture.client.currentConfiguration()
        let currentSession = await fixture.client.currentSession()
        XCTAssertEqual(currentConfiguration?.serverURL, issuingServerURL)
        XCTAssertEqual(fixture.settings.serverConfiguration?.serverURL, issuingServerURL)
        XCTAssertEqual(currentSession, session)
        XCTAssertEqual(fixture.settings.lastSession, session)
        XCTAssertEqual(fixture.tokenStore.storedToken, session.token)
    }

    func testNewInitiationRejectsOldSecretWithoutSendingIt() async throws {
        let recorder = QuickConnectRequestRecorder()
        let sequence = QuickConnectInitiationSequence()
        let fixture = makeQuickConnectFixture(
            persistedServerURL: URL(string: "https://a.example/old")!,
            requestHandler: { request in
                await recorder.record(request)
                if request.url?.path.hasSuffix("/QuickConnect/Initiate") == true {
                    let response = await sequence.next()
                    return quickConnectHTTPResponse(for: request, body: response)
                }
                return quickConnectHTTPResponse(for: request, body: #"{"Authenticated":false}"#)
            }
        )

        let oldState = try await fixture.client.initiateQuickConnect(
            serverURL: URL(string: "https://b.example/first")!
        )
        _ = try await fixture.client.initiateQuickConnect(
            serverURL: URL(string: "https://b.example/second")!
        )

        do {
            _ = try await fixture.client.pollQuickConnect(secret: oldState.secret)
            XCTFail("Expected a superseded Quick Connect secret to be rejected")
        } catch AppError.unauthenticated {
            // Expected: a superseded capability is rejected before network I/O.
        }

        let destinations = await recorder.destinations
        XCTAssertEqual(destinations.count, 2)
    }

    func testLateInitiationResponseCannotReplaceNewerHandshake() async throws {
        let gate = QuickConnectRequestGate()
        let recorder = QuickConnectRequestRecorder()
        let fixture = makeQuickConnectFixture(
            persistedServerURL: URL(string: "https://a.example/old")!,
            requestHandler: { request in
                await recorder.record(request)
                if request.url?.host == "first.example" {
                    await gate.blockUntilReleased()
                    return quickConnectHTTPResponse(
                        for: request,
                        body: #"{"Code":"OLD1","Secret":"old-synthetic-secret","Authenticated":false}"#
                    )
                }
                if request.url?.path.hasSuffix("/QuickConnect/Initiate") == true {
                    return quickConnectHTTPResponse(
                        for: request,
                        body: #"{"Code":"NEW2","Secret":"new-synthetic-secret","Authenticated":false}"#
                    )
                }
                return quickConnectHTTPResponse(for: request, body: #"{"Authenticated":false}"#)
            }
        )

        let oldInitiation = Task {
            try await fixture.client.initiateQuickConnect(
                serverURL: URL(string: "https://first.example/jellyfin")!
            )
        }
        await gate.waitUntilBlocked()
        let newState = try await fixture.client.initiateQuickConnect(
            serverURL: URL(string: "https://second.example/jellyfin")!
        )
        await gate.release()

        do {
            _ = try await oldInitiation.value
            XCTFail("Expected the late initiation response to be rejected")
        } catch AppError.unauthenticated {
            // Expected: only the newest initiation may install pending state.
        }

        _ = try await fixture.client.pollQuickConnect(secret: newState.secret)
        let destinations = await recorder.destinations
        XCTAssertEqual(destinations.last?.host, "second.example")
        XCTAssertEqual(destinations.last?.path, "/jellyfin/QuickConnect/Connect")
    }

    func testLateConnectResponseCannotExchangeOrPersistAfterNewInitiation() async throws {
        let gate = QuickConnectRequestGate()
        let recorder = QuickConnectRequestRecorder()
        let sequence = QuickConnectInitiationSequence()
        let oldServerURL = URL(string: "https://a.example/old")!
        let fixture = makeQuickConnectFixture(
            persistedServerURL: oldServerURL,
            persistedSession: UserSession(userID: "user-a", username: "User A", token: "token-a"),
            persistedToken: "token-a",
            requestHandler: { request in
                await recorder.record(request)
                if request.url?.path.hasSuffix("/QuickConnect/Initiate") == true {
                    return quickConnectHTTPResponse(for: request, body: await sequence.next())
                }
                if request.url?.path.hasSuffix("/QuickConnect/Connect") == true {
                    await gate.blockUntilReleased()
                    return quickConnectHTTPResponse(for: request, body: #"{"Authenticated":true}"#)
                }
                return quickConnectHTTPResponse(
                    for: request,
                    body: #"{"User":{"Id":"stale-user","Name":"Stale User"},"AccessToken":"stale-token"}"#
                )
            }
        )

        let oldState = try await fixture.client.initiateQuickConnect(
            serverURL: URL(string: "https://b.example/first")!
        )
        let oldPoll = Task { try await fixture.client.pollQuickConnect(secret: oldState.secret) }
        await gate.waitUntilBlocked()
        _ = try await fixture.client.initiateQuickConnect(
            serverURL: URL(string: "https://b.example/second")!
        )
        await gate.release()

        do {
            _ = try await oldPoll.value
            XCTFail("Expected a late connect response to be rejected")
        } catch AppError.unauthenticated {
            // Expected: the generation changed while the request was suspended.
        }

        let destinations = await recorder.destinations
        XCTAssertFalse(destinations.contains { $0.path.hasSuffix("/Users/AuthenticateWithQuickConnect") })
        XCTAssertEqual(fixture.settings.serverConfiguration?.serverURL, oldServerURL)
        XCTAssertEqual(fixture.tokenStore.storedToken, "token-a")
    }

    func testLateExchangeResponseCannotPersistAfterNewInitiation() async throws {
        let gate = QuickConnectRequestGate()
        let recorder = QuickConnectRequestRecorder()
        let sequence = QuickConnectInitiationSequence()
        let oldServerURL = URL(string: "https://a.example/old")!
        let oldSession = UserSession(userID: "user-a", username: "User A", token: "token-a")
        let fixture = makeQuickConnectFixture(
            persistedServerURL: oldServerURL,
            persistedSession: oldSession,
            persistedToken: oldSession.token,
            requestHandler: { request in
                await recorder.record(request)
                if request.url?.path.hasSuffix("/QuickConnect/Initiate") == true {
                    return quickConnectHTTPResponse(for: request, body: await sequence.next())
                }
                if request.url?.path.hasSuffix("/QuickConnect/Connect") == true {
                    return quickConnectHTTPResponse(for: request, body: #"{"Authenticated":true}"#)
                }
                await gate.blockUntilReleased()
                return quickConnectHTTPResponse(
                    for: request,
                    body: #"{"User":{"Id":"stale-user","Name":"Stale User"},"AccessToken":"stale-token"}"#
                )
            }
        )

        let oldState = try await fixture.client.initiateQuickConnect(
            serverURL: URL(string: "https://b.example/first")!
        )
        let oldPoll = Task { try await fixture.client.pollQuickConnect(secret: oldState.secret) }
        await gate.waitUntilBlocked()
        _ = try await fixture.client.initiateQuickConnect(
            serverURL: URL(string: "https://b.example/second")!
        )
        await gate.release()

        do {
            _ = try await oldPoll.value
            XCTFail("Expected a late exchange response to be rejected")
        } catch AppError.unauthenticated {
            // Expected: no stale exchange response may commit authentication state.
        }

        let currentConfiguration = await fixture.client.currentConfiguration()
        let currentSession = await fixture.client.currentSession()
        XCTAssertEqual(currentConfiguration?.serverURL, oldServerURL)
        XCTAssertEqual(currentSession, oldSession)
        XCTAssertEqual(fixture.settings.lastSession, oldSession)
        XCTAssertEqual(fixture.tokenStore.storedToken, oldSession.token)
    }

    func testSignOutInvalidatesPendingHandshake() async throws {
        let recorder = QuickConnectRequestRecorder()
        let fixture = makeQuickConnectFixture(
            persistedServerURL: URL(string: "https://a.example/old")!,
            recorder: recorder
        )
        let state = try await fixture.client.initiateQuickConnect(
            serverURL: URL(string: "https://b.example/jellyfin")!
        )

        await fixture.client.signOut()

        do {
            _ = try await fixture.client.pollQuickConnect(secret: state.secret)
            XCTFail("Expected sign-out to invalidate pending Quick Connect state")
        } catch AppError.unauthenticated {
            // Expected: sign-out revokes the pending capability locally.
        }
        let destinations = await recorder.destinations
        XCTAssertEqual(destinations.count, 1)
    }

    func testIssuingOriginNormalizesSchemeHostDefaultPortAndBasePath() async throws {
        let recorder = QuickConnectRequestRecorder()
        let fixture = makeQuickConnectFixture(
            persistedServerURL: URL(string: "https://a.example/old")!,
            recorder: recorder
        )

        let state = try await fixture.client.initiateQuickConnect(
            serverURL: URL(string: "HTTPS://B.Example:443/jellyfin///")!
        )
        _ = try await fixture.client.pollQuickConnect(secret: state.secret)

        let destinations = await recorder.destinations
        XCTAssertEqual(
            destinations,
            [
                QuickConnectRequestDestination(host: "b.example", path: "/jellyfin/QuickConnect/Initiate"),
                QuickConnectRequestDestination(host: "b.example", path: "/jellyfin/QuickConnect/Connect"),
                QuickConnectRequestDestination(host: "b.example", path: "/jellyfin/Users/AuthenticateWithQuickConnect")
            ]
        )
        let currentConfiguration = await fixture.client.currentConfiguration()
        XCTAssertEqual(currentConfiguration?.serverURL.absoluteString, "https://b.example/jellyfin")
    }

    func testInitiationRejectsAmbiguousOrUnsupportedOriginsBeforeNetworkIO() async throws {
        let recorder = QuickConnectRequestRecorder()
        let fixture = makeQuickConnectFixture(
            persistedServerURL: URL(string: "https://a.example/old")!,
            recorder: recorder
        )
        let invalidOrigins = [
            URL(string: "https://user:password@b.example/jellyfin")!,
            URL(string: "https://b.example/jellyfin?redirect=a")!,
            URL(string: "https://b.example/jellyfin#fragment")!,
            URL(string: "ftp://b.example/jellyfin")!
        ]

        for origin in invalidOrigins {
            do {
                _ = try await fixture.client.initiateQuickConnect(serverURL: origin)
                XCTFail("Expected an ambiguous or unsupported origin to be rejected")
            } catch AppError.invalidServerURL {
                // Expected: origin validation happens before a request is created.
            }
        }

        let destinations = await recorder.destinations
        XCTAssertEqual(destinations.count, 0)
    }
}

private struct QuickConnectTestFixture {
    let client: JellyfinAPIClient
    let settings: QuickConnectSettingsStore
    let tokenStore: QuickConnectTokenStore
}

private func makeQuickConnectFixture(
    persistedServerURL: URL,
    persistedSession: UserSession? = nil,
    persistedToken: String? = nil,
    recorder: QuickConnectRequestRecorder
) -> QuickConnectTestFixture {
    makeQuickConnectFixture(
        persistedServerURL: persistedServerURL,
        persistedSession: persistedSession,
        persistedToken: persistedToken,
        requestHandler: { request in
            await recorder.record(request)
            return try standardQuickConnectResponse(for: request)
        }
    )
}

private func makeQuickConnectFixture(
    persistedServerURL: URL,
    persistedSession: UserSession? = nil,
    persistedToken: String? = nil,
    requestHandler: @escaping @Sendable (URLRequest) async throws -> (HTTPURLResponse, Data)
) -> QuickConnectTestFixture {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [QuickConnectURLProtocolStub.self]
    QuickConnectURLProtocolStub.requestHandler = requestHandler

    let settings = QuickConnectSettingsStore(
        serverConfiguration: ServerConfiguration(serverURL: persistedServerURL),
        lastSession: persistedSession
    )
    let tokenStore = QuickConnectTokenStore(storedToken: persistedToken)
    let client = JellyfinAPIClient(
        tokenStore: tokenStore,
        settingsStore: settings,
        session: URLSession(configuration: configuration)
    )
    return QuickConnectTestFixture(client: client, settings: settings, tokenStore: tokenStore)
}

private func standardQuickConnectResponse(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
    let responseBody: String
    switch request.url?.path {
    case let path where path?.hasSuffix("/QuickConnect/Initiate") == true:
        responseBody = #"{"Code":"B123","Secret":"synthetic-secret","Authenticated":false}"#
    case let path where path?.hasSuffix("/QuickConnect/Connect") == true:
        responseBody = #"{"Authenticated":true}"#
    case let path where path?.hasSuffix("/Users/AuthenticateWithQuickConnect") == true:
        responseBody = #"{"User":{"Id":"user-b","Name":"User B"},"AccessToken":"synthetic-token"}"#
    default:
        throw URLError(.badURL)
    }
    return quickConnectHTTPResponse(for: request, body: responseBody)
}

private func quickConnectHTTPResponse(
    for request: URLRequest,
    body: String
) -> (HTTPURLResponse, Data) {
    (
        HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!,
        Data(body.utf8)
    )
}

private struct QuickConnectRequestDestination: Equatable, Sendable {
    let host: String?
    let path: String
}

private actor QuickConnectRequestRecorder {
    private(set) var destinations: [QuickConnectRequestDestination] = []

    func record(_ request: URLRequest) {
        destinations.append(
            QuickConnectRequestDestination(
                host: request.url?.host,
                path: request.url?.path ?? ""
            )
        )
    }
}

private actor QuickConnectInitiationSequence {
    private var count = 0

    func next() -> String {
        count += 1
        if count == 1 {
            return #"{"Code":"OLD1","Secret":"old-synthetic-secret","Authenticated":false}"#
        }
        return #"{"Code":"NEW2","Secret":"new-synthetic-secret","Authenticated":false}"#
    }
}

private actor QuickConnectRequestGate {
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

private final class QuickConnectURLProtocolStub: URLProtocol, @unchecked Sendable {
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

private final class QuickConnectSettingsStore: SettingsStoreProtocol, @unchecked Sendable {
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

private final class QuickConnectTokenStore: TokenStoreProtocol, @unchecked Sendable {
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
