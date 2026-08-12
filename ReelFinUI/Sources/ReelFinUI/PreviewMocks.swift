import PlaybackEngine
import JellyfinAPI
import Shared
import SwiftUI
import UIKit

final class MockJellyfinAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    var sessionInvalidations: AsyncStream<SessionInvalidationEvent> {
        sessionInvalidationsOverride?() ?? defaultSessionInvalidations
    }

    private var config: ServerConfiguration?
    private var session: UserSession?
    private let defaultSessionInvalidations: AsyncStream<SessionInvalidationEvent>
    private let sessionInvalidationsOverride: (@Sendable () -> AsyncStream<SessionInvalidationEvent>)?
    private let currentSessionOverride: (@Sendable () async -> UserSession?)?
    private let testConnectionOverride: (@Sendable (URL) async throws -> Void)?
    private let initiateQuickConnectOverride: (@Sendable (URL) async throws -> QuickConnectState)?
    private let pollQuickConnectOverride: (@Sendable (String) async throws -> UserSession?)?
    private(set) var configureCallCount = 0
    private(set) var testConnectionCallCount = 0
    private(set) var authenticateCallCount = 0

    init(
        authenticated: Bool = true,
        sessionInvalidations: AsyncStream<SessionInvalidationEvent> = AsyncStream { $0.finish() },
        sessionInvalidationsOverride: (@Sendable () -> AsyncStream<SessionInvalidationEvent>)? = nil,
        currentSessionOverride: (@Sendable () async -> UserSession?)? = nil,
        testConnectionOverride: (@Sendable (URL) async throws -> Void)? = nil,
        initiateQuickConnectOverride: (@Sendable (URL) async throws -> QuickConnectState)? = nil,
        pollQuickConnectOverride: (@Sendable (String) async throws -> UserSession?)? = nil
    ) {
        config = ServerConfiguration(serverURL: URL(string: "https://demo.reelfin.app")!)
        session = authenticated ? UserSession(userID: "preview-user", username: "Avery Morgan", token: "token") : nil
        defaultSessionInvalidations = sessionInvalidations
        self.sessionInvalidationsOverride = sessionInvalidationsOverride
        self.currentSessionOverride = currentSessionOverride
        self.testConnectionOverride = testConnectionOverride
        self.initiateQuickConnectOverride = initiateQuickConnectOverride
        self.pollQuickConnectOverride = pollQuickConnectOverride
    }

    func currentConfiguration() async -> ServerConfiguration? {
        config
    }

    func currentSession() async -> UserSession? {
        if let currentSessionOverride {
            return await currentSessionOverride()
        }
        return session
    }

    func configure(server: ServerConfiguration) async throws {
        configureCallCount += 1
        config = server
    }

    func testConnection(serverURL: URL) async throws {
        testConnectionCallCount += 1
        if let testConnectionOverride {
            try await testConnectionOverride(serverURL)
        }
    }

    func authenticate(credentials: UserCredentials) async throws -> UserSession {
        authenticateCallCount += 1
        if ProcessInfo.processInfo.arguments.contains("-reelfin-mock-auth-failure") {
            throw AppError.unauthenticated
        }
        let newSession = UserSession(userID: "preview-user", username: credentials.username, token: "token")
        session = newSession
        return newSession
    }

    func signOut() async {
        session = nil
    }

    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState {
        if let initiateQuickConnectOverride {
            return try await initiateQuickConnectOverride(serverURL)
        }
        return QuickConnectState(code: "1234", secret: "mock-secret")
    }

    func pollQuickConnect(secret: String) async throws -> UserSession? {
        if let pollQuickConnectOverride {
            return try await pollQuickConnectOverride(secret)
        }
        return nil
    }

    func fetchUserViews() async throws -> [Shared.LibraryView] {
        [Shared.LibraryView(id: "movies", name: "Movies", collectionType: "movies")]
    }

    func fetchItem(id: String) async throws -> MediaItem {
        Self.item(for: id)
    }

    func fetchSeasons(seriesID: String) async throws -> [MediaItem] {
        [
            MediaItem(id: "\(seriesID)-season1", name: "Season 1", mediaType: .season, indexNumber: 1),
            MediaItem(id: "\(seriesID)-season2", name: "Season 2", mediaType: .season, indexNumber: 2)
        ]
    }

    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] {
        if seriesID == "series-continue-1" {
            return Self.continueWatchingEpisodes()
        }

        let series = Self.item(for: seriesID)
        let episodeCopy: [(name: String, overview: String)] = [
            ("The First Entry", "A new line appears in the almanac overnight, guiding Elian toward a clock tower no map records."),
            ("Blue Ink", "Mara follows a water-stained prediction through the old market while the town prepares for an unexpected eclipse."),
            ("The Quiet Forecast", "A page left intentionally blank begins filling with the smallest choices made by everyone in the valley."),
            ("North of Midnight", "The almanac points beyond the last streetlight, where Elian finds a message written in his own handwriting."),
            ("Tomorrow's Margin", "As the final page turns, Mara must decide whether a prediction is a promise, a warning, or an invitation.")
        ]

        return episodeCopy.enumerated().map { index, copy in
            MediaItem(
                id: "\(seriesID)-episode-\(index + 1)",
                name: copy.name,
                overview: copy.overview,
                mediaType: .episode,
                year: series.year,
                runtimeTicks: Int64((42 + index) * 60 * 10_000_000),
                genres: series.genres,
                communityRating: 7.8 + Double(index % 3) * 0.1,
                posterTag: "poster",
                backdropTag: "backdrop",
                libraryID: "shows",
                parentID: seriesID,
                seriesName: series.name,
                seriesPosterTag: series.posterTag,
                indexNumber: index + 1,
                parentIndexNumber: 1
            )
        }
    }

    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? {
        if seriesID == "series-continue-1" {
            return Self.continueWatchingEpisodes()[1]
        }

        let eps = try await fetchEpisodes(seriesID: seriesID, seasonID: "season1")
        return eps.first
    }

    func fetchNextUpEpisodes(limit: Int) async throws -> [MediaItem] {
        Array(Self.continueWatchingEpisodes().prefix(limit))
    }

    func fetchHomeFeed(since: Date?) async throws -> HomeFeed {
        let releasedMovies = Self.storefrontItems(prefix: 8).enumerated().map { index, item -> MediaItem in
            var copy = item
            copy.mediaType = .movie
            copy.year = 2026 - (index % 3)
            return copy
        }
        let releasedSeries = Self.storefrontItems(prefix: 8).enumerated().map { index, item -> MediaItem in
            var copy = item
            copy.id = "released-series-\(index)"
            copy.mediaType = .series
            copy.year = 2026 - (index % 2)
            return copy
        }
        let recentMovies = Self.storefrontItems(prefix: 8).map { item -> MediaItem in
            var copy = item
            copy.mediaType = .movie
            return copy
        }
        let recentSeries = Self.storefrontItems(prefix: 8).map { item -> MediaItem in
            var copy = item
            copy.mediaType = .series
            return copy
        }
        return HomeFeed(featured: Self.storefrontItems(prefix: 5), rows: [
            HomeRow(kind: .continueWatching, title: "Continue Watching", items: Self.continueWatchingItems()),
            HomeRow(kind: .recentlyReleasedMovies, title: "Recently Released Movies", items: releasedMovies),
            HomeRow(kind: .recentlyReleasedSeries, title: "Recently Released TV Shows", items: releasedSeries),
            HomeRow(kind: .recentlyAddedMovies, title: "Recently Added Movies", items: recentMovies),
            HomeRow(kind: .recentlyAddedSeries, title: "Recently Added TV", items: recentSeries)
        ])
    }

    func fetchItemDetail(id: String) async throws -> MediaDetail {
        let item = Self.item(for: id)
        return MediaDetail(item: item, similar: Self.storefrontItems(prefix: 8), cast: [
            PersonCredit(id: "1", name: "Mara Ellison", role: "Iria Vale", primaryImageTag: "primary"),
            PersonCredit(id: "2", name: "Theo Arden", role: "Jonas Saye", primaryImageTag: "primary")
        ])
    }

    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] {
        var items = Self.storefrontItems(prefix: 40)
        if let mediaType = query.mediaType {
            items = items.filter { $0.mediaType == mediaType }
        }

        let pageSize = max(query.pageSize, 0)
        let startIndex = max(query.page, 0) * pageSize
        guard startIndex < items.count else { return [] }
        return Array(items.dropFirst(startIndex).prefix(pageSize))
    }

    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] {
        [
            MediaSource(
                id: "source-1",
                itemID: itemID,
                name: "Original Quality",
                container: "mp4",
                videoCodec: "h264",
                audioCodec: "aac",
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"),
                directPlayURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"),
                transcodeURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"),
                audioTracks: [MediaTrack(id: "audio-1", title: "English", language: "en", isDefault: true, index: 0)],
                subtitleTracks: [MediaTrack(id: "sub-1", title: "English CC", language: "en", isDefault: true, index: 0)]
            )
        ]
    }

    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? {
        if type == .logo {
            return nil
        }
        let normalizedWidth = width.map { type.normalizedImageWidth($0) } ?? 400
        return URL(string: "mock-image://\(itemID)?type=\(type.rawValue)&width=\(normalizedWidth)")
    }

    func reportPlayback(progress: PlaybackProgressUpdate) async throws {}

    func reportPlayed(itemID: String) async throws {}

    static func storefrontItems(prefix: Int) -> [MediaItem] {
        let entries: [(title: String, overview: String, genres: [String])] = [
            ("Vesper Meridian", "A solitary cartographer follows a luminous current across an uncharted sea and discovers a coastline that redraws itself each night.", ["Adventure", "Mystery"]),
            ("Lattice of Rain", "Two estranged sisters restore a weather observatory where every storm carries fragments of a forgotten melody.", ["Drama", "Mystery"]),
            ("The Quiet Cartographer", "An apprentice mapmaker uncovers a hidden district whose streets appear only to people searching for a second chance.", ["Drama", "Fantasy"]),
            ("Copperlight", "A night-shift engineer receives impossible radio calls from a city that vanished beyond the northern horizon decades ago.", ["Science Fiction", "Thriller"]),
            ("Aster Vale", "A botanist returns to her mountain village as rare flowers begin blooming in patterns that mirror the stars above.", ["Drama", "Fantasy"]),
            ("Signal at Caldera", "A rescue crew enters a silent volcanic station and finds one final transmission counting down to sunrise.", ["Thriller", "Adventure"]),
            ("Mothglass", "A museum conservator discovers that the colors in an antique window change whenever someone nearby tells the truth.", ["Mystery", "Drama"]),
            ("Orbit of Ash", "The last courier between two drifting colonies must cross a field of burning debris before their shared oxygen runs out.", ["Science Fiction", "Adventure"]),
            ("The Last Blue Hour", "On the longest evening of summer, four old friends follow a trail of lanterns toward the promise they once abandoned.", ["Drama", "Adventure"]),
            ("Juniper Static", "A community radio host hears tomorrow's local news hidden beneath the static and tries to change one impossible headline.", ["Mystery", "Drama"]),
            ("Echoes of Kestrel", "A sound archivist climbs an abandoned signal tower to recover the final recording of a celebrated explorer.", ["Mystery", "Adventure"]),
            ("Velvet Current", "A competitive free diver follows a warm underwater current toward a reef missing from every nautical chart.", ["Adventure", "Drama"]),
            ("Night Bloom Protocol", "When a citywide garden awakens after dark, a systems designer must decode the flowers before the power grid fails.", ["Science Fiction", "Mystery"]),
            ("The Paper Horizon", "A young illustrator finds that every landscape she folds from paper becomes a doorway for exactly one minute.", ["Fantasy", "Adventure"]),
            ("Sundial North", "Three researchers race across a frozen valley where shadows move in reverse and daylight is quickly disappearing.", ["Adventure", "Thriller"]),
            ("Mercury Garden", "An orbital horticulturist protects a fragile greenhouse while a silver storm closes around the station.", ["Science Fiction", "Drama"]),
            ("Cinder Atlas", "A railway photographer follows a midnight train whose passengers each carry a map to a place they have lost.", ["Mystery", "Drama"]),
            ("Palewater", "A harbor pilot guides an unfamiliar vessel through dense fog and learns why its crew refuses to look toward shore.", ["Mystery", "Thriller"]),
            ("Lanterns at Zero", "At a remote winter festival, a clockmaker and a chef uncover the secret keeping every lantern alight without flame.", ["Drama", "Mystery"]),
            ("The Ember Archive", "A librarian safeguards the last collection of handwritten memories as a wildfire approaches the valley.", ["Drama", "Adventure"]),
            ("Cloudbreakers", "A fearless glider team crosses a chain of floating islands to deliver medicine before the seasonal winds turn.", ["Adventure", "Fantasy"]),
            ("Marble Sleep", "An architect wakes inside an unfinished hotel where each room preserves a different version of the same day.", ["Mystery", "Thriller"]),
            ("Fable Circuit", "A game designer discovers an obsolete console that tells new stories about anyone who holds its controller.", ["Science Fiction", "Mystery"]),
            ("The Arctic Room", "A climate researcher opens a sealed laboratory and finds a perfectly preserved summer afternoon waiting inside.", ["Science Fiction", "Drama"]),
            ("Hollow Aurora", "Beneath a silent aurora, a wilderness guide leads six travelers toward a refuge that may exist only in their memories.", ["Adventure", "Mystery"]),
            ("Postcards from Luna", "A postal worker begins receiving beautifully stamped letters from the first lunar settlement, thirty years too early.", ["Science Fiction", "Drama"]),
            ("The Long Frequency", "Two amateur astronomers trace a repeating signal to an abandoned cinema at the edge of their coastal town.", ["Mystery", "Science Fiction"]),
            ("Citadel of Salt", "A marine historian enters a fortress revealed by the lowest tide in a century and races the returning sea.", ["Adventure", "Mystery"]),
            ("Wildlight", "A documentary crew follows a rare ribbon of light through the forest and finds a village missing from modern maps.", ["Adventure", "Drama"]),
            ("River of Glass", "A courier skates across a frozen river carrying a mysterious package that grows warmer with every mile.", ["Thriller", "Adventure"]),
            ("Twelve Moons", "A school astronomer notices a new moon appearing each midnight and recruits her neighbors to solve the celestial puzzle.", ["Fantasy", "Mystery"]),
            ("Saffron Skies", "A retired pilot returns to the desert airfield where a brilliant amber cloud has grounded every plane except hers.", ["Adventure", "Drama"]),
            ("The Indigo Hour", "During the brief hour when the city turns blue, a violinist can hear the private wishes of everyone passing by.", ["Drama", "Fantasy"]),
            ("Horizon Relay", "A bicycle messenger crosses a storm-darkened metropolis to reconnect a chain of rooftop emergency beacons.", ["Adventure", "Thriller"]),
            ("Low Tide Signals", "Three siblings return to their island home and decode blinking lights beneath the harbor at every low tide.", ["Mystery", "Drama"]),
            ("Axiom Grove", "A mathematician retreats to an orchard where the branches grow into elegant proofs of questions no one has asked.", ["Science Fiction", "Drama"]),
            ("Blue Ember", "A ceramic artist discovers a flame that burns cold and attracts visitors carrying stories they have never shared.", ["Drama", "Fantasy"]),
            ("The Velvet Comet", "A small observatory prepares for a once-in-a-lifetime comet while an unexpected guest changes the viewing plan.", ["Drama", "Science Fiction"]),
            ("Glimmer Coast", "A lighthouse keeper and her daughter follow phosphorescent footprints along a shore erased by morning.", ["Mystery", "Fantasy"]),
            ("The Night Almanac", "An antique bookseller finds an almanac that predicts only the quiet decisions capable of changing an entire town.", ["Drama", "Mystery"])
        ]

        return entries.prefix(prefix).enumerated().map { index, entry in
            let mediaType: MediaType = index.isMultiple(of: 2) ? .movie : .series
            let runtimeTicks = Int64((95 + index * 3) * 60 * 10_000_000)
            let rating = 7.4 + Double(index % 13) * 0.1

            return MediaItem(
                id: "sample-\(index)",
                name: entry.title,
                overview: entry.overview,
                mediaType: mediaType,
                year: 2022 + (index % 5),
                runtimeTicks: runtimeTicks,
                genres: entry.genres,
                communityRating: rating,
                posterTag: "poster",
                backdropTag: "backdrop",
                libraryID: "movies"
            )
        }
    }

    private static func continueWatchingItems() -> [MediaItem] {
        let resumeEpisode = continueWatchingEpisodes()[1]
        let resumeMovie = MediaItem(
            id: "cw-movie-1",
            name: "Northbound Signal",
            overview: "A mountain dispatcher follows a fading distress signal into a valley where every compass points toward the same deserted cabin.",
            mediaType: .movie,
            year: 2024,
            runtimeTicks: Int64(112 * 60 * 10_000_000),
            genres: ["Adventure"],
            communityRating: 7.8,
            posterTag: "poster",
            backdropTag: "backdrop",
            libraryID: "movies",
            has4K: true,
            isPlayed: false,
            playbackPositionTicks: Int64(41 * 60 * 10_000_000)
        )

        return [resumeEpisode, resumeMovie] + storefrontItems(prefix: 6)
    }

    private static func continueWatchingEpisodes() -> [MediaItem] {
        [
            MediaItem(
                id: "cw-episode-1",
                name: "First Light",
                overview: "Mira reaches the remote observatory and discovers a signal hidden inside the first sunrise of the season.",
                mediaType: .episode,
                year: 2025,
                runtimeTicks: Int64(24 * 60 * 10_000_000),
                genres: ["Drama"],
                communityRating: 7.9,
                posterTag: "poster",
                backdropTag: "backdrop",
                libraryID: "shows",
                parentID: "series-continue-1",
                seriesName: "Antenna Falls",
                seriesPosterTag: "poster",
                indexNumber: 1,
                parentIndexNumber: 1,
                isPlayed: true,
                playbackPositionTicks: Int64(24 * 60 * 10_000_000)
            ),
            MediaItem(
                id: "cw-episode-2",
                name: "Second Horizon",
                overview: "A sudden blackout forces Mira and Rowan to carry the observatory's last transmitter across the ridge before dawn.",
                mediaType: .episode,
                year: 2025,
                runtimeTicks: Int64(27 * 60 * 10_000_000),
                genres: ["Drama"],
                communityRating: 8.1,
                posterTag: "poster",
                backdropTag: "backdrop",
                libraryID: "shows",
                parentID: "series-continue-1",
                seriesName: "Antenna Falls",
                seriesPosterTag: "poster",
                indexNumber: 2,
                parentIndexNumber: 1,
                isPlayed: false,
                playbackPositionTicks: Int64((11 * 60 + 12) * 10_000_000)
            )
        ]
    }

    private static func item(for id: String) -> MediaItem {
        if let match = continueWatchingItems().first(where: { $0.id == id }) {
            return match
        }

        if id == "series-continue-1" {
            return MediaItem(
                id: "series-continue-1",
                name: "Antenna Falls",
                overview: "At a secluded observatory, two radio astronomers trace an impossible signal through the mountains and into their shared past.",
                mediaType: .series,
                year: 2025,
                runtimeTicks: Int64(27 * 60 * 10_000_000),
                genres: ["Drama"],
                communityRating: 8.1,
                posterTag: "poster",
                backdropTag: "backdrop",
                libraryID: "shows"
            )
        }

        if id.hasPrefix("sample-"),
           let index = Int(id.dropFirst("sample-".count)),
           index >= 0 {
            return storefrontItems(prefix: index + 1)[index]
        }

        return MediaItem(id: id, name: "Fictional Feature")
    }
}

final class MockSettingsStore: SettingsStoreProtocol, @unchecked Sendable {
    var serverConfiguration: ServerConfiguration?
    var lastSession: UserSession?
    var episodeReleaseNotificationsEnabled = false
    var hasCompletedOnboarding: Bool
    var completedOnboardingVersion: Int
    var useCustomPlayerEngine = false

    init(authenticated: Bool = true) {
        serverConfiguration = ServerConfiguration(serverURL: URL(string: "https://demo.reelfin.app")!)
        lastSession = authenticated ? UserSession(userID: "preview-user", username: "Avery Morgan", token: "token") : nil
        hasCompletedOnboarding = authenticated
        completedOnboardingVersion = authenticated ? ReelFinOnboardingVersion.current : 0
    }
}

actor MockMetadataRepository: MetadataRepositoryProtocol {
    private var homeFeed: HomeFeed = HomeFeed.empty
    private var itemsByID: [String: MediaItem] = [:]

    func saveLibraryViews(_ views: [Shared.LibraryView]) async throws {}
    func fetchLibraryViews() async throws -> [Shared.LibraryView] { [] }

    func saveHomeFeed(_ feed: HomeFeed) async throws {
        homeFeed = feed
        for item in feed.featured + feed.rows.flatMap(\.items) {
            itemsByID[item.id] = item
        }
    }

    func fetchHomeFeed() async throws -> HomeFeed {
        if homeFeed.rows.isEmpty {
            homeFeed = try await MockJellyfinAPIClient().fetchHomeFeed(since: nil)
        }
        return homeFeed
    }

    func upsertItems(_ items: [MediaItem]) async throws {
        for item in items {
            itemsByID[item.id] = item
        }
    }

    func fetchItem(id: String) async throws -> MediaItem? {
        itemsByID[id]
    }

    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] {
        var items = itemsByID.values.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        if let mediaType = query.mediaType {
            items = items.filter { $0.mediaType == mediaType }
        }

        let pageSize = max(query.pageSize, 0)
        let startIndex = max(query.page, 0) * pageSize
        guard startIndex < items.count else { return [] }
        return Array(items.dropFirst(startIndex).prefix(pageSize))
    }

    func searchItems(query: String, limit: Int) async throws -> [MediaItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let catalog = MockJellyfinAPIClient.storefrontItems(prefix: 40)
        let matches = catalog.filter { item in
            guard !normalizedQuery.isEmpty else { return true }
            let searchableCopy = [
                item.name,
                item.overview ?? "",
                item.genres.joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            return searchableCopy.contains(normalizedQuery)
        }
        return Array(matches.prefix(limit))
    }

    func savePlaybackProgress(_ progress: PlaybackProgress) async throws {}
    func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress? { nil }

    func fetchLastSyncDate() async throws -> Date? { nil }
    func setLastSyncDate(_ date: Date) async throws {}
}

final class MockImagePipeline: ImagePipelineProtocol, @unchecked Sendable {
    func image(for url: URL) async throws -> UIImage {
        ArtworkPlaceholderRenderer.makeImage(for: url)
    }

    func image(for url: URL, consumer consumerID: ImageRequestConsumerID) async throws -> UIImage {
        _ = consumerID
        return try await image(for: url)
    }

    func cachedImage(for url: URL) async -> UIImage? {
        ArtworkPlaceholderRenderer.makeImage(for: url)
    }

    func prefetch(urls: [URL]) async {}

    func cancel(url: URL) {}

    func cancel(url: URL, consumer consumerID: ImageRequestConsumerID) {
        _ = consumerID
    }
}

private enum ArtworkPlaceholderRenderer {
    static func makeImage(for url: URL) -> UIImage {
        let isBackdrop = url.absoluteString.lowercased().contains("type=backdrop")
        let size = isBackdrop
            ? CGSize(width: 1920, height: 1080)
            : CGSize(width: 900, height: 1350)
        return makeImage(seed: url.absoluteString, size: size)
    }

    static func makeImage(seed: String, size: CGSize = CGSize(width: 900, height: 1350)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let palette = palette(for: seed)
        let stableHash = StorefrontStableSeed.hash(seed)

        return renderer.image { context in
            let cgContext = context.cgContext

            let gradientColors = palette.map(\.cgColor) as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0, 0.55, 1])!

            cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            let unit = min(size.width, size.height)
            let phase = CGFloat(stableHash % 360) * .pi / 180
            let center = CGPoint(
                x: size.width * (0.46 + 0.12 * cos(phase)),
                y: size.height * (0.44 + 0.10 * sin(phase))
            )

            cgContext.saveGState()
            cgContext.setBlendMode(.screen)
            for index in 0..<4 {
                let inset = CGFloat(index) * unit * 0.07
                let diameter = unit * 0.70 - inset * 2
                let ring = CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.12 - CGFloat(index) * 0.018).cgColor)
                cgContext.setLineWidth(max(2, unit * (0.012 - CGFloat(index) * 0.0015)))
                cgContext.strokeEllipse(in: ring)
            }

            let beam = CGMutablePath()
            let beamOffset = CGFloat((stableHash >> 12) % 100) / 100
            beam.move(to: CGPoint(x: -size.width * 0.15, y: size.height * (0.66 + beamOffset * 0.08)))
            beam.addLine(to: CGPoint(x: size.width * 1.08, y: size.height * (0.18 + beamOffset * 0.10)))
            beam.addLine(to: CGPoint(x: size.width * 1.16, y: size.height * (0.31 + beamOffset * 0.08)))
            beam.addLine(to: CGPoint(x: -size.width * 0.08, y: size.height * (0.80 + beamOffset * 0.06)))
            beam.closeSubpath()
            cgContext.addPath(beam)
            cgContext.setFillColor(UIColor.white.withAlphaComponent(0.075).cgColor)
            cgContext.fillPath()

            let orbDiameter = unit * 0.20
            let orb = CGRect(
                x: center.x - orbDiameter / 2,
                y: center.y - orbDiameter / 2,
                width: orbDiameter,
                height: orbDiameter
            )
            cgContext.setFillColor(UIColor.white.withAlphaComponent(0.20).cgColor)
            cgContext.fillEllipse(in: orb)
            cgContext.restoreGState()

            let vignetteColors = [
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.58).cgColor
            ] as CFArray
            if let vignette = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: vignetteColors,
                locations: [0.40, 1]
            ) {
                cgContext.drawRadialGradient(
                    vignette,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: max(size.width, size.height) * 0.82,
                    options: [.drawsAfterEndLocation]
                )
            }
        }
    }

    private static func palette(for seed: String) -> [UIColor] {
        let palettes: [[UIColor]] = [
            [UIColor(red: 0.07, green: 0.10, blue: 0.18, alpha: 1), UIColor(red: 0.17, green: 0.30, blue: 0.54, alpha: 1), UIColor(red: 0.03, green: 0.64, blue: 0.89, alpha: 1)],
            [UIColor(red: 0.20, green: 0.07, blue: 0.16, alpha: 1), UIColor(red: 0.54, green: 0.16, blue: 0.29, alpha: 1), UIColor(red: 0.89, green: 0.36, blue: 0.29, alpha: 1)],
            [UIColor(red: 0.10, green: 0.18, blue: 0.12, alpha: 1), UIColor(red: 0.18, green: 0.40, blue: 0.24, alpha: 1), UIColor(red: 0.62, green: 0.83, blue: 0.39, alpha: 1)],
            [UIColor(red: 0.11, green: 0.08, blue: 0.20, alpha: 1), UIColor(red: 0.28, green: 0.20, blue: 0.55, alpha: 1), UIColor(red: 0.72, green: 0.48, blue: 0.96, alpha: 1)]
        ]

        let index = StorefrontStableSeed.paletteIndex(for: seed, paletteCount: palettes.count)
        return palettes[index]
    }
}

enum StorefrontStableSeed {
    static func hash(_ value: String) -> UInt64 {
        value.utf8.reduce(into: UInt64(14_695_981_039_346_656_037)) { hash, byte in
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
    }

    static func paletteIndex(for value: String, paletteCount: Int) -> Int {
        precondition(paletteCount > 0)
        return Int(hash(value) % UInt64(paletteCount))
    }
}

final class MockSyncEngine: SyncEngineProtocol, @unchecked Sendable {
    func sync(reason: SyncReason) async {}
}

public enum ReelFinPreviewFactory {
    @MainActor public static func dependencies(authenticated: Bool = true) -> ReelFinDependencies {
        dependencies(
            authenticated: authenticated,
            apiClient: MockJellyfinAPIClient(authenticated: authenticated)
        )
    }

    @MainActor static func dependencies(
        authenticated: Bool = true,
        apiClient: MockJellyfinAPIClient
    ) -> ReelFinDependencies {
        let api = apiClient
        let repository = MockMetadataRepository()
        let detailRepository = DefaultMediaDetailRepository(
            apiClient: api,
            repository: repository,
            itemTTL: 60,
            detailTTL: 60,
            collectionTTL: 60
        )
        let images = MockImagePipeline()
        let sync = MockSyncEngine()
        let settings = MockSettingsStore(authenticated: authenticated)
        let notifications = NoopEpisodeReleaseNotificationManager()
        let seriesCache = SeriesLookupCache(apiClient: api)
        let warmupManager = PlaybackWarmupManager(apiClient: api, ttl: 60)
        let tvFocusWarmupCoordinator = TVFocusWarmupCoordinator(
            settleDelayNanoseconds: 0,
            maxConcurrentJobs: 1
        )

        return ReelFinDependencies(
            apiClient: api,
            repository: repository,
            detailRepository: detailRepository,
            imagePipeline: images,
            syncEngine: sync,
            settingsStore: settings,
            episodeReleaseNotificationManager: notifications,
            seriesCache: seriesCache,
            playbackWarmupManager: warmupManager,
            tvFocusWarmupCoordinator: tvFocusWarmupCoordinator,
            makePlaybackSession: {
                PlaybackSessionController(
                    apiClient: api,
                    repository: repository,
                    warmupManager: warmupManager
                )
            }
        )
    }

    @MainActor public static func appStoreDependencies(authenticated: Bool = true) -> ReelFinDependencies {
        dependencies(authenticated: authenticated)
    }
}

#Preview {
    ReelFinRootView(dependencies: ReelFinPreviewFactory.dependencies())
}
