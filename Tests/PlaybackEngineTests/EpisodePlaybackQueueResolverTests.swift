@testable import ReelFinUI
import Shared
import XCTest

final class EpisodePlaybackQueueResolverTests: XCTestCase {
    func testFollowingEpisodesContinueIntoNextSeasonWithoutRepeatingCurrentEpisode() {
        let seasonOne = MediaItem(
            id: "season-1",
            name: "Season 1",
            mediaType: .season,
            indexNumber: 1
        )
        let seasonTwo = MediaItem(
            id: "season-2",
            name: "Season 2",
            mediaType: .season,
            indexNumber: 2
        )
        let episodeOne = episode(id: "s1e1", season: 1, number: 1)
        let episodeTwo = episode(id: "s1e2", season: 1, number: 2)
        let episodeThree = episode(id: "s1e3", season: 1, number: 3)
        let nextSeasonPilot = episode(id: "s2e1", season: 2, number: 1)

        let queue = EpisodePlaybackQueueResolver.followingEpisodes(
            after: episodeTwo,
            seasons: [seasonTwo, seasonOne],
            episodesBySeasonID: [
                seasonOne.id: [episodeOne, episodeTwo, episodeThree, episodeThree],
                seasonTwo.id: [nextSeasonPilot]
            ]
        )

        XCTAssertEqual(queue.map(\.id), ["s1e3", "s2e1"])
    }

    func testFollowingEpisodesReturnsEmptyWhenCurrentEpisodeCannotBeLocated() {
        let seasonOne = MediaItem(
            id: "season-1",
            name: "Season 1",
            mediaType: .season,
            indexNumber: 1
        )

        let queue = EpisodePlaybackQueueResolver.followingEpisodes(
            after: episode(id: "missing", season: 1, number: 9),
            seasons: [seasonOne],
            episodesBySeasonID: [seasonOne.id: [episode(id: "s1e1", season: 1, number: 1)]]
        )

        XCTAssertTrue(queue.isEmpty)
    }

    func testLoadFollowingEpisodesSkipsEmptySeasonsUntilNextEpisodeIsFound() async {
        let seasonOne = MediaItem(
            id: "season-1",
            name: "Season 1",
            mediaType: .season,
            indexNumber: 1
        )
        let seasonTwo = MediaItem(
            id: "season-2",
            name: "Season 2",
            mediaType: .season,
            indexNumber: 2
        )
        let seasonThree = MediaItem(
            id: "season-3",
            name: "Season 3",
            mediaType: .season,
            indexNumber: 3
        )
        let currentEpisode = episode(id: "s1e1", season: 1, number: 1)
        let nextEpisode = episode(id: "s3e1", season: 3, number: 1)
        let repository = QueueDetailRepositoryStub(
            seasons: [seasonOne, seasonTwo, seasonThree],
            episodesBySeasonID: [
                seasonOne.id: [currentEpisode],
                seasonThree.id: [nextEpisode]
            ]
        )

        let queue = await EpisodePlaybackQueueResolver.loadFollowingEpisodes(
            after: currentEpisode,
            repository: repository
        )

        XCTAssertEqual(queue.map(\.id), [nextEpisode.id])
    }

    private func episode(id: String, season: Int, number: Int) -> MediaItem {
        MediaItem(
            id: id,
            name: id,
            mediaType: .episode,
            parentID: "series-1",
            indexNumber: number,
            parentIndexNumber: season
        )
    }
}

private final class QueueDetailRepositoryStub: MediaDetailRepositoryProtocol, @unchecked Sendable {
    private let seasons: [MediaItem]
    private let episodesBySeasonID: [String: [MediaItem]]

    init(seasons: [MediaItem], episodesBySeasonID: [String: [MediaItem]]) {
        self.seasons = seasons
        self.episodesBySeasonID = episodesBySeasonID
    }

    func cachedItem(id: String) async -> MediaItem? { nil }
    func refreshItem(id: String) async throws -> MediaItem { throw StubError.notImplemented }
    func loadDetail(id: String) async throws -> MediaDetail { throw StubError.notImplemented }
    func loadSeasons(seriesID: String) async throws -> [MediaItem] { seasons }
    func loadEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] {
        episodesBySeasonID[seasonID] ?? []
    }
    func loadNextUpEpisode(seriesID: String) async throws -> MediaItem? { nil }
    func primeItem(id: String) async {}
    func primeDetail(id: String) async {}

    private enum StubError: Error {
        case notImplemented
    }
}
