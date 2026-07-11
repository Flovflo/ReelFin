import Foundation
import Shared

/// A hermetic, DEBUG-only tvOS switch for the live Jellyfin player journey. The UI test receives
/// only this non-sensitive alias; lookup happens inside the already-authenticated application.
public enum TVLiveUIAutomationPolicy {
    public static let starCityEpisodeOneAlias = "star-city-s1e1"

    public static func isEnabled(
        isDebug: Bool,
        isTVOS: Bool,
        environment: [String: String]
    ) -> Bool {
        guard isDebug, isTVOS else { return false }
        guard truthy(environment["REELFIN_TV_UI_AUTOMATION"]) else { return false }
        return environment["REELFIN_LIVE_UI_FIXTURE_ALIAS"] == starCityEpisodeOneAlias
    }

    public static var isEnabledForCurrentProcess: Bool {
#if DEBUG && os(tvOS)
        isEnabled(isDebug: true, isTVOS: true, environment: ProcessInfo.processInfo.environment)
#else
        false
#endif
    }

    public static func minimumLoopCount(requested: Int) -> Int {
        max(10, requested)
    }

    public static func fixturePlaybackItem(_ item: MediaItem) -> MediaItem {
        guard isEnabledForCurrentProcess else { return item }
        var fixture = item
        fixture.isPlayed = false
        fixture.playbackPositionTicks = 440 * 10_000_000
        return fixture
    }

    private static func truthy(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }
}

enum TVLiveUIFixtureResolver {
    static func resolveStarCityEpisodeOne(
        apiClient: any JellyfinAPIClientProtocol
    ) async throws -> MediaItem? {
        let series = try await apiClient.fetchLibraryItems(
            query: LibraryQuery(
                viewID: nil,
                page: 0,
                pageSize: 20,
                query: "Star City",
                mediaType: .series
            )
        )
        guard let matchingSeries = series.first(where: {
            $0.name.compare("Star City", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { return nil }

        let seasons = try await apiClient.fetchSeasons(seriesID: matchingSeries.id)
        guard let seasonOne = seasons.first(where: { $0.indexNumber == 1 }) else { return nil }
        let episodes = try await apiClient.fetchEpisodes(
            seriesID: matchingSeries.id,
            seasonID: seasonOne.id
        )
        guard let episodeOne = episodes.first(where: {
            $0.parentIndexNumber == 1 && $0.indexNumber == 1
        }) else { return nil }
        return TVLiveUIAutomationPolicy.fixturePlaybackItem(episodeOne)
    }
}
