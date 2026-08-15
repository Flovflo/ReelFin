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

    static func isHomeFocusEvidenceEnabled(
        isDebug: Bool,
        isTVOS: Bool,
        environment: [String: String]
    ) -> Bool {
        isDebug && isTVOS && truthy(environment["REELFIN_TV_UI_AUTOMATION"])
    }

    static var isHomeFocusEvidenceEnabledForCurrentProcess: Bool {
#if DEBUG && os(tvOS)
        isHomeFocusEvidenceEnabled(
            isDebug: true,
            isTVOS: true,
            environment: ProcessInfo.processInfo.environment
        )
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

struct TVHomeFocusTransitionCounter: Equatable {
    private(set) var count = 0

    mutating func recordChange(from oldValue: String?, to newValue: String?) {
        guard oldValue != newValue else { return }
        count += 1
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

enum LiveUIPlaybackScenario: String, CaseIterable, Sendable {
    case directPlayMP4 = "directplay-mp4"
    case directPlayHDRDolbyVisionLong = "directplay-hdr-dv-long"
    case sampleBufferMKV = "samplebuffer-mkv"
}

/// Resolves a closed, non-sensitive scenario inside the authenticated app. The runner prepares
/// the requested fixture as a Resume item; no Jellyfin item identifier crosses the launch boundary.
enum LiveUIPlaybackFixtureResolver {
    static func resolve(
        scenario: LiveUIPlaybackScenario,
        apiClient: any JellyfinAPIClientProtocol
    ) async throws -> MediaItem? {
        let feed = try await apiClient.fetchHomeFeed(since: nil)
        let resumeItems = feed.rows.first(where: { $0.kind == .continueWatching })?.items ?? []
        for item in resumeItems {
            let sources = try await apiClient.fetchPlaybackSources(itemID: item.id)
            if sources.contains(where: { matches(source: $0, scenario: scenario) }) {
                return item
            }
        }
        return nil
    }

    static func matches(source: MediaSource, scenario: LiveUIPlaybackScenario) -> Bool {
        let containers = Set(source.normalizedContainer
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        switch scenario {
        case .directPlayMP4:
            return !containers.isDisjoint(with: ["mp4", "mov", "m4v"])
                && source.supportsDirectPlay
                && !source.hasExplicitHDRorDVSignaling
        case .directPlayHDRDolbyVisionLong:
            return !containers.isDisjoint(with: ["mp4", "mov", "m4v"])
                && source.supportsDirectPlay
                && isDolbyVision(source)
        case .sampleBufferMKV:
            return !containers.isDisjoint(with: ["mkv", "matroska", "webm"])
        }
    }

    private static func isDolbyVision(_ source: MediaSource) -> Bool {
        let values = [
            source.videoRange,
            source.videoRangeType,
            source.videoProfile,
            source.videoCodec,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        return (source.dvProfile ?? 0) > 0
            || values.contains("dovi")
            || values.contains("dolby vision")
            || values.contains("dvhe")
            || values.contains("dvh1")
    }
}
