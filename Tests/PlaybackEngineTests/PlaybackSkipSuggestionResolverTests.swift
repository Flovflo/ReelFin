import Shared
import XCTest
@testable import PlaybackEngine

final class PlaybackSkipSuggestionResolverTests: XCTestCase {
    func testIntroSegmentProducesSkipIntroSuggestion() {
        let item = MediaItem(
            id: "episode-1",
            name: "Episode 1",
            mediaType: .episode,
            runtimeTicks: 1_800_000_000
        )
        let segments = [
            MediaSegment(
                id: "segment-1",
                itemID: item.id,
                type: .intro,
                startTicks: 0,
                endTicks: 300_000_000
            )
        ]

        let suggestion = PlaybackSkipSuggestionResolver.suggestion(
            segments: segments,
            currentTime: 5,
            duration: 1_800,
            currentItem: item,
            nextEpisodeQueue: []
        )

        XCTAssertEqual(suggestion?.title, "Skip Intro")
        guard case let .seek(to: targetSeconds)? = suggestion?.target else {
            return XCTFail("Expected a seek suggestion")
        }
        XCTAssertEqual(targetSeconds, 30.5, accuracy: 0.001)
    }

    func testOutroSegmentProducesNextEpisodeSuggestionWhenQueueExists() {
        let item = MediaItem(
            id: "episode-1",
            name: "Episode 1",
            mediaType: .episode,
            runtimeTicks: 1_800_000_000
        )
        let nextEpisode = MediaItem(
            id: "episode-2",
            name: "Episode 2",
            mediaType: .episode,
            runtimeTicks: 1_800_000_000
        )
        let segments = [
            MediaSegment(
                id: "segment-2",
                itemID: item.id,
                type: .outro,
                startTicks: 1_500_000_000,
                endTicks: 1_800_000_000
            )
        ]

        let suggestion = PlaybackSkipSuggestionResolver.suggestion(
            segments: segments,
            currentTime: 165,
            duration: 180,
            currentItem: item,
            nextEpisodeQueue: [nextEpisode]
        )

        XCTAssertEqual(suggestion?.title, "Next Episode")
        XCTAssertEqual(suggestion?.target, .nextEpisode)
    }
}
