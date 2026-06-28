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

            let requestURL = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
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
                    url: requestURL,
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

    func testHomeFeedRecentlyReleasedTVShowsUseRecentEpisodesAndIgnoreIncrementalDate() async throws {
        let recorder = LibraryAggregationRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JellyfinLibraryURLProtocolStub.self]
        JellyfinLibraryURLProtocolStub.requestHandler = { request in
            await recorder.record(request)

            let requestURL = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
            let queryItems = components.queryItems ?? []
            let includeTypes = queryItems.first(where: { $0.name == "IncludeItemTypes" })?.value
            let sortBy = queryItems.first(where: { $0.name == "SortBy" })?.value

            let payload: String
            switch (components.path, includeTypes, sortBy) {
            case ("/Users/user-1/Items/Resume", _, _):
                payload = #"{"Items":[]}"#
            case (_, "Episode", "PremiereDate"):
                payload = """
                {
                  "Items": [
                    {
                      "Id": "episode-future-show",
                      "Name": "Future Episode",
                      "Type": "Episode",
                      "SeriesId": "series-future",
                      "SeriesName": "Future Show",
                      "PremiereDate": "2999-05-02T20:00:00Z"
                    },
                    {
                      "Id": "episode-undated-show",
                      "Name": "Undated Episode",
                      "Type": "Episode",
                      "SeriesId": "series-undated",
                      "SeriesName": "Undated Show"
                    },
                    {
                      "Id": "episode-the-boys-s5",
                      "Name": "S5 Premiere",
                      "Type": "Episode",
                      "SeriesId": "series-the-boys",
                      "SeriesName": "The Boys",
                      "PremiereDate": "2026-05-02T20:00:00Z"
                    },
                    {
                      "Id": "episode-silo-old",
                      "Name": "Older Episode",
                      "Type": "Episode",
                      "SeriesId": "series-silo",
                      "SeriesName": "Silo",
                      "PremiereDate": "2025-01-17T20:00:00Z"
                    },
                    {
                      "Id": "episode-the-boys-duplicate",
                      "Name": "Duplicate Same Series",
                      "Type": "Episode",
                      "SeriesId": "series-the-boys",
                      "SeriesName": "The Boys",
                      "PremiereDate": "2025-01-10T20:00:00Z"
                    }
                  ]
                }
                """
            case ("/Users/user-1/Items/series-the-boys", _, _):
                payload = """
                {
                  "Id": "series-the-boys",
                  "Name": "The Boys",
                  "Type": "Series",
                  "ImageTags": { "Primary": "boys-poster" },
                  "ProductionYear": 2019
                }
                """
            case ("/Users/user-1/Items/series-future", _, _):
                payload = """
                {
                  "Id": "series-future",
                  "Name": "Future Show",
                  "Type": "Series",
                  "ImageTags": { "Primary": "future-poster" },
                  "ProductionYear": 2999
                }
                """
            case ("/Users/user-1/Items/series-undated", _, _):
                payload = """
                {
                  "Id": "series-undated",
                  "Name": "Undated Show",
                  "Type": "Series",
                  "ImageTags": { "Primary": "undated-poster" },
                  "ProductionYear": 2026
                }
                """
            case ("/Users/user-1/Items/series-silo", _, _):
                payload = """
                {
                  "Id": "series-silo",
                  "Name": "Silo",
                  "Type": "Series",
                  "ImageTags": { "Primary": "silo-poster" },
                  "ProductionYear": 2023
                }
                """
            default:
                payload = #"{"Items":[]}"#
            }

            return (
                HTTPURLResponse(
                    url: requestURL,
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

        let feed = try await client.fetchHomeFeed(since: Date(timeIntervalSince1970: 1_700_000_000))
        let releasedTVRow = try XCTUnwrap(feed.rows.first(where: { $0.kind == .recentlyReleasedSeries }))

        XCTAssertEqual(releasedTVRow.title, "Recently Released TV Shows")
        XCTAssertEqual(releasedTVRow.items.map(\.id), ["series-the-boys", "series-silo"])
        XCTAssertEqual(releasedTVRow.items.map(\.mediaType), [.series, .series])

        let requests = await recorder.requests
        let releasedTVRequest = try XCTUnwrap(requests.first { request in
            guard
                let url = request.url,
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return false }

            let queryItems = components.queryItems ?? []
            return queryItems.contains(URLQueryItem(name: "IncludeItemTypes", value: "Episode"))
                && queryItems.contains(URLQueryItem(name: "SortBy", value: "PremiereDate"))
        })
        let releasedTVQueryItems = URLComponents(
            url: try XCTUnwrap(releasedTVRequest.url),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []

        XCTAssertTrue(releasedTVQueryItems.contains(URLQueryItem(name: "IsMissing", value: "false")))
        XCTAssertTrue(releasedTVQueryItems.contains(URLQueryItem(name: "IsUnaired", value: "false")))
        XCTAssertNil(releasedTVQueryItems.first(where: { $0.name == "MinDateLastSavedForUser" }))
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
    var useCustomPlayerEngine = false

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
