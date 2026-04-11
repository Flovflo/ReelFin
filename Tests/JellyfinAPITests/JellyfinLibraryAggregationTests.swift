import Foundation
import JellyfinAPI
import Shared
import XCTest

final class JellyfinLibraryAggregationTests: XCTestCase {
    override func tearDown() {
        JellyfinLibraryURLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testFetchLibraryItemsAggregatesMultipleViewsAndPreservesLibraryID() async throws {
        let recorder = LibraryAggregationRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JellyfinLibraryURLProtocolStub.self]
        JellyfinLibraryURLProtocolStub.requestHandler = { request in
            await recorder.record(request)

            let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let parentID = components.queryItems?.first(where: { $0.name == "ParentId" })?.value

            let payload: String
            switch parentID {
            case "movies-a":
                payload = """
                {
                  "Items": [
                    { "Id": "movie-a-1", "Name": "Movie A 1", "Type": "Movie", "ProductionYear": 2025 },
                    { "Id": "movie-a-2", "Name": "Movie A 2", "Type": "Movie", "ProductionYear": 2024 }
                  ]
                }
                """
            case "movies-b":
                payload = """
                {
                  "Items": [
                    { "Id": "movie-b-1", "Name": "Movie B 1", "Type": "Movie", "ProductionYear": 2023 },
                    { "Id": "movie-b-2", "Name": "Movie B 2", "Type": "Movie", "ProductionYear": 2022 }
                  ]
                }
                """
            default:
                XCTFail("Unexpected ParentId \(parentID ?? "nil")")
                payload = #"{"Items":[]}"#
            }

            return (
                HTTPURLResponse(
                    url: XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(payload.utf8)
            )
        }

        let session = URLSession(configuration: configuration)
        let settings = LibraryAggregationSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://example.com")!),
            lastSession: UserSession(userID: "user-1", username: "Flo", token: "token-1")
        )
        let tokenStore = LibraryAggregationTokenStore(storedToken: "token-1")
        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings, session: session)

        let items = try await client.fetchLibraryItems(
            query: LibraryQuery(
                viewIDs: ["movies-a", "movies-b"],
                page: 0,
                pageSize: 4,
                query: nil,
                mediaType: .movie
            )
        )

        XCTAssertEqual(Set(items.map(\.id)), ["movie-a-1", "movie-a-2", "movie-b-1", "movie-b-2"])
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.libraryID) }),
            [
                "movie-a-1": "movies-a",
                "movie-a-2": "movies-a",
                "movie-b-1": "movies-b",
                "movie-b-2": "movies-b"
            ]
        )

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 2)

        let parentIDs = requests.compactMap { request in
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "ParentId" })?
                .value
        }
        XCTAssertEqual(Set(parentIDs), ["movies-a", "movies-b"])
    }
}

private actor LibraryAggregationRequestRecorder {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }
}

private final class JellyfinLibraryURLProtocolStub: URLProtocol, @unchecked Sendable {
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

private final class LibraryAggregationSettingsStore: SettingsStoreProtocol, @unchecked Sendable {
    var serverConfiguration: ServerConfiguration?
    var lastSession: UserSession?
    var episodeReleaseNotificationsEnabled = false
    var hasCompletedOnboarding = false
    var completedOnboardingVersion = 0

    init(serverConfiguration: ServerConfiguration?, lastSession: UserSession?) {
        self.serverConfiguration = serverConfiguration
        self.lastSession = lastSession
    }
}

private final class LibraryAggregationTokenStore: TokenStoreProtocol, @unchecked Sendable {
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
