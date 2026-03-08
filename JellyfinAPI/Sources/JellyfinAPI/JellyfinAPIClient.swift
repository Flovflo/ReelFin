import Foundation
import Shared

private struct EmptyResponse: Decodable {}

private struct HTTPStatusError: Error {
    let statusCode: Int
    let message: String
}

public actor JellyfinAPIClient: JellyfinAPIClientProtocol {
    private enum ClientDefaultsKeys {
        static let deviceID = "jellyfin.client.device_id"
    }

    private let tokenStore: TokenStoreProtocol
    private let settingsStore: SettingsStoreProtocol
    private let urlSession: URLSession
    private let retryPolicy: RetryPolicy
    private let clientName: String
    private let deviceName: String
    private let deviceID: String
    private let clientVersion: String
    private let deduplicator = RequestDeduplicator()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let iso8601 = ISO8601DateFormatter()

    private var configuration: ServerConfiguration?
    private var activeSession: UserSession?

    public init(
        tokenStore: TokenStoreProtocol = KeychainTokenStore(),
        settingsStore: SettingsStoreProtocol = DefaultSettingsStore(),
        session: URLSession = .shared,
        retryPolicy: RetryPolicy = .init(),
        clientName: String = "ReelFin",
        deviceName: String = "iOS",
        deviceID: String? = nil,
        clientVersion: String? = nil
    ) {
        self.tokenStore = tokenStore
        self.settingsStore = settingsStore
        self.urlSession = session
        self.retryPolicy = retryPolicy
        self.clientName = clientName
        self.deviceName = deviceName
        self.deviceID = deviceID ?? Self.defaultDeviceID()
        self.clientVersion = clientVersion ?? Self.defaultClientVersion()
        self.configuration = settingsStore.serverConfiguration
        self.activeSession = settingsStore.lastSession

        if let keychainToken = try? tokenStore.fetchToken(), var sessionValue = self.activeSession {
            sessionValue.token = keychainToken
            self.activeSession = sessionValue
            self.settingsStore.lastSession = sessionValue
        }
    }

    public func currentConfiguration() async -> ServerConfiguration? {
        configuration
    }

    public func currentSession() async -> UserSession? {
        activeSession
    }

    public func configure(server: ServerConfiguration) async throws {
        configuration = server
        settingsStore.serverConfiguration = server
    }

    public func testConnection(serverURL: URL) async throws {
        let url = try buildURL(baseURL: serverURL, path: "System/Info/Public", query: [])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(embyAuthorizationHeader(token: nil), forHTTPHeaderField: "X-Emby-Authorization")
        _ = try await send(request, dedupe: true)
    }

    public func authenticate(credentials: UserCredentials) async throws -> UserSession {
        let body = AuthenticateRequestDTO(username: credentials.username, pw: credentials.password)
        let response: AuthenticateResponseDTO = try await request(
            path: "Users/AuthenticateByName",
            method: "POST",
            body: body,
            requiresAuth: false,
            dedupe: false
        )

        let session = UserSession(userID: response.user.id, username: response.user.name, token: response.accessToken)
        activeSession = session
        settingsStore.lastSession = session
        try tokenStore.saveToken(response.accessToken)
        return session
    }

    public func signOut() async {
        activeSession = nil
        settingsStore.lastSession = nil
        try? tokenStore.clearToken()
        await deduplicator.cancelAll()
    }

    public func fetchUserViews() async throws -> [LibraryView] {
        let userID = try requireUserID()
        let response: ViewsResponseDTO = try await request(path: "Users/\(userID)/Views")
        return response.items.map { LibraryView(id: $0.id, name: $0.name, collectionType: $0.collectionType) }
    }

    public func fetchHomeFeed(since: Date?) async throws -> HomeFeed {
        let userID = try requireUserID()

        async let resumeItems = fetchItems(
            userID: userID,
            path: "Users/\(userID)/Items/Resume",
            query: [
                URLQueryItem(name: "Limit", value: "20")
            ],
            libraryID: nil
        )

        async let popularItems = fetchItems(
            userID: userID,
            path: "Users/\(userID)/Items",
            query: [
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Limit", value: "20"),
                URLQueryItem(name: "SortBy", value: "CommunityRating,SortName"),
                URLQueryItem(name: "SortOrder", value: "Descending")
            ] + incrementalQuery(since: since),
            libraryID: nil
        )

        async let nextUpEpisodes = fetchItems(
            userID: userID,
            path: "Shows/NextUp",
            query: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "Limit", value: "20"),
                URLQueryItem(name: "Fields", value: "Overview,MediaStreams,AirDays,UserData"),
                URLQueryItem(name: "EnableResumable", value: "true"),
                URLQueryItem(name: "EnableRewatching", value: "false")
            ],
            libraryID: nil
        )

        async let recentlyAddedMovies = fetchItems(
            userID: userID,
            path: "Users/\(userID)/Items",
            query: [
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IncludeItemTypes", value: "Movie"),
                URLQueryItem(name: "Limit", value: "20"),
                URLQueryItem(name: "SortBy", value: "DateCreated"),
                URLQueryItem(name: "SortOrder", value: "Descending")
            ] + incrementalQuery(since: since),
            libraryID: nil
        )

        async let recentlyAddedSeries = fetchItems(
            userID: userID,
            path: "Users/\(userID)/Items",
            query: [
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IncludeItemTypes", value: "Series"),
                URLQueryItem(name: "Limit", value: "20"),
                URLQueryItem(name: "SortBy", value: "DateCreated"),
                URLQueryItem(name: "SortOrder", value: "Descending")
            ] + incrementalQuery(since: since),
            libraryID: nil
        )

        async let trendingItems = fetchItems(
            userID: userID,
            path: "Users/\(userID)/Items",
            query: [
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Limit", value: "20"),
                URLQueryItem(name: "SortBy", value: "DateCreated,SortName"),
                URLQueryItem(name: "SortOrder", value: "Descending")
            ] + incrementalQuery(since: since),
            libraryID: nil
        )

        async let movies = fetchItems(
            userID: userID,
            path: "Users/\(userID)/Items",
            query: [
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IncludeItemTypes", value: "Movie"),
                URLQueryItem(name: "Limit", value: "20"),
                URLQueryItem(name: "SortBy", value: "DateCreated")
            ] + incrementalQuery(since: since),
            libraryID: nil
        )

        async let shows = fetchItems(
            userID: userID,
            path: "Users/\(userID)/Items",
            query: [
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IncludeItemTypes", value: "Series"),
                URLQueryItem(name: "Limit", value: "20"),
                URLQueryItem(name: "SortBy", value: "PremiereDate")
            ] + incrementalQuery(since: since),
            libraryID: nil
        )

        let resume = (try? await resumeItems) ?? []
        let nextUp = (try? await nextUpEpisodes) ?? []
        let recentMovieItems = (try? await recentlyAddedMovies) ?? []
        let recentSeriesItems = (try? await recentlyAddedSeries) ?? []
        let popular = (try? await popularItems) ?? []
        let trending = (try? await trendingItems) ?? []
        let movieItems = (try? await movies) ?? []
        let showItems = (try? await shows) ?? []

        let featured = Array((recentMovieItems + recentSeriesItems + popular).prefix(8))
        let rows = [
            HomeRow(kind: .continueWatching, title: "Continue Watching", items: resume),
            HomeRow(kind: .nextUp, title: "Next Up", items: nextUp),
            HomeRow(kind: .recentlyAddedMovies, title: "Recently Added Movies", items: recentMovieItems),
            HomeRow(kind: .recentlyAddedSeries, title: "Recently Added Series", items: recentSeriesItems),
            HomeRow(kind: .popular, title: "Popular", items: popular),
            HomeRow(kind: .trending, title: "Trending", items: trending),
            HomeRow(kind: .movies, title: "Movies", items: movieItems),
            HomeRow(kind: .shows, title: "Shows", items: showItems)
        ]

        return HomeFeed(featured: featured, rows: rows)
    }

    public func fetchItem(id: String) async throws -> MediaItem {
        let userID = try requireUserID()
        let item: ItemDTO = try await request(
            path: "Users/\(userID)/Items/\(id)",
            query: [
                URLQueryItem(name: "Fields", value: "Genres,Overview,PrimaryImageAspectRatio,RunTimeTicks,People,MediaStreams,AirDays")
            ]
        )
        return item.toDomain()
    }

    public func fetchItemDetail(id: String) async throws -> MediaDetail {
        let userID = try requireUserID()
        let item: ItemDTO = try await request(
            path: "Users/\(userID)/Items/\(id)",
            query: [
                URLQueryItem(name: "Fields", value: "Genres,Overview,PrimaryImageAspectRatio,RunTimeTicks,People,MediaStreams,AirDays")
            ]
        )

        let similarResponse: ItemsResponseDTO = try await request(
            path: "Items/\(id)/Similar",
            query: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "Limit", value: "20")
            ]
        )

        return MediaDetail(
            item: item.toDomain(),
            similar: similarResponse.items.map { $0.toDomain() },
            cast: (item.people ?? []).map { $0.toDomain() }
        )
    }

    public func fetchSeasons(seriesID: String) async throws -> [MediaItem] {
        let userID = try requireUserID()
        let response: ItemsResponseDTO = try await request(
            path: "Shows/\(seriesID)/Seasons",
            query: [
                URLQueryItem(name: "UserId", value: userID)
            ]
        )
        return response.items.map { $0.toDomain() }
    }

    public func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] {
        let userID = try requireUserID()
        let response: ItemsResponseDTO = try await request(
            path: "Shows/\(seriesID)/Episodes",
            query: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "SeasonId", value: seasonID),
                URLQueryItem(name: "Fields", value: "Overview")
            ]
        )
        return response.items.map { $0.toDomain() }
    }

    public func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? {
        let userID = try requireUserID()
        // Use the dedicated NextUp endpoint, filtered to this series.
        // enableResumable=true (default) means in-progress episodes are returned first.
        let response: ItemsResponseDTO = try await request(
            path: "Shows/NextUp",
            query: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "SeriesId", value: seriesID),
                URLQueryItem(name: "Limit", value: "1"),
                URLQueryItem(name: "Fields", value: "Overview"),
                URLQueryItem(name: "EnableResumable", value: "true"),
                URLQueryItem(name: "EnableRewatching", value: "false")
            ]
        )
        return response.items.first?.toDomain()
    }

    public func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] {
        let userID = try requireUserID()
        var queryItems = [
            URLQueryItem(name: "UserId", value: userID),
            URLQueryItem(name: "StartIndex", value: String(query.page * query.pageSize)),
            URLQueryItem(name: "Limit", value: String(query.pageSize)),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "SortBy", value: "DateCreated,SortName"),
            URLQueryItem(name: "SortOrder", value: "Descending")
        ]

        if let viewID = query.viewID {
            queryItems.append(URLQueryItem(name: "ParentId", value: viewID))
        }

        if let search = query.query, !search.isEmpty {
            queryItems.append(URLQueryItem(name: "SearchTerm", value: search))
        }

        if let mediaType = query.mediaType {
            switch mediaType {
            case .movie:
                queryItems.append(URLQueryItem(name: "IncludeItemTypes", value: "Movie"))
            case .series:
                queryItems.append(URLQueryItem(name: "IncludeItemTypes", value: "Series"))
            case .episode:
                queryItems.append(URLQueryItem(name: "IncludeItemTypes", value: "Episode"))
            case .season:
                queryItems.append(URLQueryItem(name: "IncludeItemTypes", value: "Season"))
            case .unknown:
                break
            }
        }

        let response: ItemsResponseDTO = try await request(path: "Users/\(userID)/Items", query: queryItems)
        return response.items.map { $0.toDomain(libraryID: query.viewID) }
    }

    public func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] {
        guard let configuration else {
            throw AppError.invalidServerURL
        }

        let options = PlaybackInfoOptions.balanced(maxStreamingBitrate: configuration.preferredQuality.maxStreamingBitrate)
        return try await fetchPlaybackSources(itemID: itemID, options: options)
    }

    public func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] {
        // OpenAPI source:
        // /Users/florian/Downloads/jellyfin-openapi-stable.json
        // $.paths["/Items/{itemId}/PlaybackInfo"].post
        let maxBitrate = options.maxStreamingBitrate ?? configuration?.preferredQuality.maxStreamingBitrate ?? 8_000_000
        let profile: DeviceProfileRequestDTO?
        switch options.deviceProfile ?? .automatic {
        case .automatic:
            profile = nil
        case .iosOptimizedHEVC:
            profile = DeviceProfileRequestDTO.iosOptimizedHEVC(
                maxStreamingBitrate: maxBitrate,
                maxAudioChannels: options.maxAudioChannels ?? 6
            )
        case .iosCompatibilityH264:
            profile = DeviceProfileRequestDTO.iosCompatibilityH264(
                maxStreamingBitrate: maxBitrate,
                maxAudioChannels: options.maxAudioChannels ?? 2
            )
        }

        let body = PlaybackInfoRequestDTO(
            userID: activeSession?.userID,
            enableDirectPlay: options.enableDirectPlay,
            enableDirectStream: options.enableDirectStream,
            enableTranscoding: options.allowTranscoding,
            maxStreamingBitrate: maxBitrate,
            startTimeTicks: options.startTimeTicks,
            allowVideoStreamCopy: options.allowVideoStreamCopy,
            allowAudioStreamCopy: options.allowAudioStreamCopy,
            maxAudioChannels: options.maxAudioChannels,
            deviceProfile: profile
        )

        let response: PlaybackInfoResponseDTO = try await request(
            path: "Items/\(itemID)/PlaybackInfo",
            method: "POST",
            body: body,
            dedupe: false
        )

        guard let configuration else {
            throw AppError.invalidServerURL
        }

        return response.mediaSources.map { $0.toDomain(itemID: itemID, serverURL: configuration.serverURL) }
    }

    public func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? {
        guard let configuration else { return nil }

        var queryItems = [URLQueryItem]()
        // Request WebP for better compression and faster transit on Apple devices.
        queryItems.append(URLQueryItem(name: "format", value: "webp"))

        if let width {
            queryItems.append(URLQueryItem(name: "maxWidth", value: String(width)))
        }
        if let quality {
            queryItems.append(URLQueryItem(name: "quality", value: String(quality)))
        }
        if let token = activeSession?.token {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }

        let imagePath: String
        if type == .backdrop {
            imagePath = "Items/\(itemID)/Images/\(type.rawValue)/0"
        } else {
            imagePath = "Items/\(itemID)/Images/\(type.rawValue)"
        }

        return try? buildURL(
            baseURL: configuration.serverURL,
            path: imagePath,
            query: queryItems
        )
    }

    public func prefetchImages(for items: [MediaItem]) async {
        // Speculative prefetching: Generate URLs and trigger URLSession tasks.
        // This warms up the server-side image cache and local CDN.
        for item in items {
            if let posterURL = await imageURL(for: item.id, type: .primary, width: 400, quality: 80) {
                let request = URLRequest(url: posterURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
                _ = try? await urlSession.data(for: request)
            }
        }
    }

    public func reportPlayback(progress: PlaybackProgressUpdate) async throws {
        let body = PlaybackProgressRequestDTO(
            itemID: progress.itemID,
            positionTicks: progress.positionTicks,
            canSeek: true,
            isPaused: progress.isPaused,
            isMuted: false,
            playMethod: progress.playMethod ?? "Transcode"
        )

        let _: EmptyResponse = try await request(
            path: "Sessions/Playing/Progress",
            method: "POST",
            body: body,
            dedupe: false
        )
    }

    public func reportPlayed(itemID: String) async throws {
        let userID = try requireUserID()
        let _: EmptyResponse = try await request(
            path: "Users/\(userID)/PlayedItems/\(itemID)",
            method: "POST",
            dedupe: false
        )
    }

    private func fetchItems(
        userID: String,
        path: String,
        query: [URLQueryItem],
        libraryID: String?
    ) async throws -> [MediaItem] {
        let response: ItemsResponseDTO = try await request(path: path, query: query)
        return response.items.map { $0.toDomain(libraryID: libraryID) }
    }

    private func incrementalQuery(since: Date?) -> [URLQueryItem] {
        guard let since else { return [] }
        return [URLQueryItem(name: "MinDateLastSavedForUser", value: iso8601.string(from: since))]
    }

    private func requireUserID() throws -> String {
        guard let session = activeSession else {
            throw AppError.unauthenticated
        }
        return session.userID
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Encodable? = nil,
        requiresAuth: Bool = true,
        dedupe: Bool = true
    ) async throws -> T {
        let request = try buildRequest(
            path: path,
            method: method,
            query: query,
            body: body,
            requiresAuth: requiresAuth
        )

        let data = try await send(request, dedupe: dedupe && method.uppercased() == "GET")

        if T.self == EmptyResponse.self || data.isEmpty {
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            // Server returned an empty body for a typed response — log and fail gracefully.
            AppLog.networking.warning("Empty response body for \(String(describing: T.self), privacy: .public)")
            throw AppError.decoding("Server returned an empty response.")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            let detail: String
            switch decodingError {
            case let .keyNotFound(key, context):
                detail = "Missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case let .typeMismatch(type, context):
                detail = "Type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
            case let .valueNotFound(type, context):
                detail = "Null value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case let .dataCorrupted(context):
                detail = "Corrupted data at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
            @unknown default:
                detail = decodingError.localizedDescription
            }
            AppLog.networking.error("Decoding failed [\(String(describing: T.self), privacy: .public)]: \(detail, privacy: .public)")
            throw AppError.decoding("Unable to decode server response.")
        } catch {
            AppLog.networking.error("Decoding failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.decoding("Unable to decode server response.")
        }
    }

    private func buildRequest(
        path: String,
        method: String,
        query: [URLQueryItem],
        body: Encodable?,
        requiresAuth: Bool
    ) throws -> URLRequest {
        guard let configuration else {
            throw AppError.invalidServerURL
        }

        let url = try buildURL(baseURL: configuration.serverURL, path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(clientName)/\(clientVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue(embyAuthorizationHeader(token: activeSession?.token), forHTTPHeaderField: "X-Emby-Authorization")

        if requiresAuth {
            guard let token = activeSession?.token else {
                throw AppError.unauthenticated
            }
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        request.timeoutInterval = 20
        return request
    }

    private func send(_ request: URLRequest, dedupe: Bool) async throws -> Data {
        let key = request.httpMethod.map { "\($0)|\(request.url?.absoluteString ?? "")" }

        do {
            return try await retrying(policy: retryPolicy, shouldRetry: self.isRetryable(error:)) { [self] in
                if dedupe, let key {
                    return try await self.deduplicator.data(for: key) {
                        try await self.execute(request: request)
                    }
                }
                return try await self.execute(request: request)
            }
        } catch let error as HTTPStatusError {
            if error.statusCode == 401 {
                throw AppError.unauthenticated
            }
            throw AppError.network("Server error (\(error.statusCode)): \(error.message)")
        } catch let error as URLError {
            throw AppError.network(error.localizedDescription)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.network(error.localizedDescription)
        }
    }

    private func execute(request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.network("Invalid network response.")
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw HTTPStatusError(statusCode: http.statusCode, message: message)
        }

        return data
    }

    nonisolated private func isRetryable(error: Error) -> Bool {
        if let statusError = error as? HTTPStatusError {
            return statusError.statusCode >= 500
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet, .cannotFindHost:
                return true
            default:
                return false
            }
        }

        if case let AppError.network(message) = error, message.lowercased().contains("timed out") {
            return true
        }

        return false
    }

    private func buildURL(baseURL: URL, path: String, query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw AppError.invalidServerURL
        }

        let sanitizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var basePath = components.path
        if basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        components.path = basePath + "/" + sanitizedPath
        components.queryItems = query.isEmpty ? nil : query

        guard let url = components.url else {
            throw AppError.invalidServerURL
        }
        return url
    }

    private func embyAuthorizationHeader(token: String?) -> String {
        var parts = [
            "Client=\"\(escaped(clientName))\"",
            "Device=\"\(escaped(deviceName))\"",
            "DeviceId=\"\(escaped(deviceID))\"",
            "Version=\"\(escaped(clientVersion))\""
        ]

        if let token, !token.isEmpty {
            parts.append("Token=\"\(escaped(token))\"")
        }

        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }

    nonisolated private static func defaultDeviceID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: ClientDefaultsKeys.deviceID), !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString
        defaults.set(generated, forKey: ClientDefaultsKeys.deviceID)
        return generated
    }

    nonisolated private static func defaultClientVersion() -> String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String
        let buildVersion = info?["CFBundleVersion"] as? String

        if let shortVersion, let buildVersion {
            return "\(shortVersion) (\(buildVersion))"
        }
        if let shortVersion {
            return shortVersion
        }
        if let buildVersion {
            return buildVersion
        }
        return "1.0"
    }
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        self.encodeClosure = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
