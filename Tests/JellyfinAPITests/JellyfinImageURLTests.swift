import Foundation
import JellyfinAPI
import Shared
import XCTest

final class JellyfinImageURLTests: XCTestCase {
    override func tearDown() {
        RemoteArtworkURLProtocol.reset()
        super.tearDown()
    }

    func testImageURLDoesNotEmbedAuthenticationToken() async throws {
        let settings = TestSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://example.com")!),
            lastSession: UserSession(userID: "user-1", username: "Flo", token: "")
        )
        let tokenStore = TestTokenStore(storedToken: "secret-token")
        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings)

        let generatedURL = await client.imageURL(for: "item-1", type: .primary, width: 640, quality: 80)
        let url = try XCTUnwrap(generatedURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertFalse(url.absoluteString.contains("api_key="))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "format" })?.value, "webp")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "maxWidth" })?.value, "640")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "quality" })?.value, "80")
    }

    func testRemoteImageURLUsesRequestedTypeDownsizesTMDBAndCachesResolution() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteArtworkURLProtocol.self]
        let settings = TestSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://jellyfin.example")!),
            lastSession: UserSession(userID: "user-1", username: "Flo", token: "")
        )
        let client = JellyfinAPIClient(
            tokenStore: TestTokenStore(storedToken: "secret-token"),
            settingsStore: settings,
            session: URLSession(configuration: configuration)
        )

        let first = await client.remoteImageURL(
            for: "series-1",
            type: .backdrop,
            width: 720
        )
        let second = await client.remoteImageURL(
            for: "series-1",
            type: .backdrop,
            width: 720
        )
        let hero = await client.remoteImageURL(
            for: "series-1",
            type: .backdrop,
            width: 1_920
        )

        XCTAssertEqual(first, URL(string: "https://image.tmdb.org/t/p/w780/backdrop.jpg"))
        XCTAssertEqual(second, first)
        XCTAssertEqual(hero, URL(string: "https://image.tmdb.org/t/p/w1280/backdrop.jpg"))
        XCTAssertEqual(RemoteArtworkURLProtocol.requestCount, 1)
        XCTAssertEqual(RemoteArtworkURLProtocol.lastType, "Backdrop")
        XCTAssertEqual(RemoteArtworkURLProtocol.lastLimit, "1")
        XCTAssertEqual(RemoteArtworkURLProtocol.lastToken, "secret-token")
    }

    func testRemoteImageResolutionBurstIsBounded() async {
        RemoteArtworkURLProtocol.responseDelay = 0.08
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteArtworkURLProtocol.self]
        let settings = TestSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://jellyfin.example")!),
            lastSession: UserSession(userID: "user-1", username: "Flo", token: "")
        )
        let client = JellyfinAPIClient(
            tokenStore: TestTokenStore(storedToken: "secret-token"),
            settingsStore: settings,
            session: URLSession(configuration: configuration)
        )

        await withTaskGroup(of: URL?.self) { group in
            for index in 0 ..< 8 {
                group.addTask {
                    await client.remoteImageURL(
                        for: "item-\(index)",
                        type: .backdrop,
                        width: 780
                    )
                }
            }
            for await _ in group {}
        }

        XCTAssertLessThanOrEqual(RemoteArtworkURLProtocol.maximumConcurrentRequests, 3)
    }

    func testCancelledQueuedRemoteImageResolutionNeverStartsNetworkWork() async {
        RemoteArtworkURLProtocol.responseDelay = 0.12
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteArtworkURLProtocol.self]
        let settings = TestSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://jellyfin.example")!),
            lastSession: UserSession(userID: "user-1", username: "Flo", token: "")
        )
        let client = JellyfinAPIClient(
            tokenStore: TestTokenStore(storedToken: "secret-token"),
            settingsStore: settings,
            session: URLSession(configuration: configuration)
        )

        let activeTasks = (0 ..< 3).map { index in
            Task {
                await client.remoteImageURL(for: "active-\(index)", type: .backdrop, width: 780)
            }
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let cancelledTask = Task {
            await client.remoteImageURL(for: "cancelled", type: .backdrop, width: 780)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        cancelledTask.cancel()

        _ = await cancelledTask.value
        for task in activeTasks {
            _ = await task.value
        }

        XCTAssertEqual(RemoteArtworkURLProtocol.requestCount, 3)
    }
}

private final class RemoteArtworkURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests = 0
    private static var type: String?
    private static var limit: String?
    private static var token: String?
    private static var activeRequests = 0
    private static var maximumActiveRequests = 0
    static var responseDelay: TimeInterval = 0

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "jellyfin.example"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        Self.lock.lock()
        Self.requests += 1
        Self.type = components?.queryItems?.first(where: { $0.name == "Type" })?.value
        Self.limit = components?.queryItems?.first(where: { $0.name == "Limit" })?.value
        Self.token = request.value(forHTTPHeaderField: "X-Emby-Token")
        Self.activeRequests += 1
        Self.maximumActiveRequests = max(Self.maximumActiveRequests, Self.activeRequests)
        let delay = Self.responseDelay
        Self.lock.unlock()

        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.sendResponse()
            }
        } else {
            sendResponse()
        }
    }

    private func sendResponse() {
        let body = Data(#"{"Images":[{"Url":"https://image.tmdb.org/t/p/original/backdrop.jpg","Type":"Backdrop","ProviderName":"TheMovieDb","Width":3840,"Height":2160}],"TotalRecordCount":1}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
        Self.lock.withLock { Self.activeRequests = max(Self.activeRequests - 1, 0) }
    }

    override func stopLoading() {}

    static func reset() {
        lock.lock()
        requests = 0
        type = nil
        limit = nil
        token = nil
        activeRequests = 0
        maximumActiveRequests = 0
        responseDelay = 0
        lock.unlock()
    }

    static var requestCount: Int { lock.withLock { requests } }
    static var lastType: String? { lock.withLock { type } }
    static var lastLimit: String? { lock.withLock { limit } }
    static var lastToken: String? { lock.withLock { token } }
    static var maximumConcurrentRequests: Int { lock.withLock { maximumActiveRequests } }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private final class TestSettingsStore: SettingsStoreProtocol, @unchecked Sendable {
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

private final class TestTokenStore: TokenStoreProtocol, @unchecked Sendable {
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
