import Shared
import XCTest

final class TVPerformanceStateTests: XCTestCase {
    func testArtworkRequestProfilesExposeExpectedBackdropTiers() {
        XCTAssertEqual(ArtworkRequestProfile.heroBackdropLow.width, 960)
        XCTAssertEqual(ArtworkRequestProfile.heroBackdropLow.quality, 68)
        XCTAssertEqual(ArtworkRequestProfile.heroBackdropHigh.width, 1_920)
        XCTAssertEqual(ArtworkRequestProfile.heroBackdropHigh.quality, 82)
    }

    func testHeroPagingPolicyKeepsNearestNeighbors() {
        let items = sampleItems(count: 6)

        let window = TVHeroPagingPolicy.contextItems(around: items[3], in: items)

        XCTAssertEqual(window.map(\.id), ["item-2", "item-3", "item-4", "item-5"])
    }

    func testLibraryPaginationPolicyUsesTrailingWindowTrigger() {
        let items = sampleItems(count: 20)

        let triggerID = TVLibraryPaginationPolicy.triggerItemID(in: items, trailingWindow: 12)

        XCTAssertEqual(triggerID, "item-8")
    }

    func testDetailNeighborNavigationStateMatchesEpisodeContextAgainstSeriesShell() {
        let contextItems = [
            MediaItem(id: "movie-1", name: "Movie 1", mediaType: .movie),
            MediaItem(
                id: "episode-1",
                name: "Episode 1",
                mediaType: .episode,
                parentID: "series-1",
                seriesName: "Series"
            ),
            MediaItem(id: "movie-2", name: "Movie 2", mediaType: .movie)
        ]
        let state = DetailNeighborNavigationState(
            currentItem: MediaItem(id: "series-1", name: "Series", mediaType: .series),
            contextItems: contextItems
        )

        XCTAssertEqual(state.currentIndex, 1)
        XCTAssertEqual(state.previousItem?.id, "movie-1")
        XCTAssertEqual(state.nextItem?.id, "movie-2")
    }

    func testFocusWarmupCoordinatorLatestScopeWins() async throws {
        let coordinator = TVFocusWarmupCoordinator(
            settleDelayNanoseconds: 40_000_000,
            maxConcurrentJobs: 1
        )
        let recorder = WarmupRecorder()

        await coordinator.schedule(scope: "home.focus", detailShell: {
            await recorder.record("first")
        })

        await coordinator.schedule(scope: "home.focus", detailShell: {
            await recorder.record("second")
        })

        try await Task.sleep(nanoseconds: 120_000_000)

        let events = await recorder.events
        XCTAssertEqual(events, ["second"])
    }

    func testFocusWarmupCoordinatorSupportsImmediateOverrideDelay() async throws {
        let coordinator = TVFocusWarmupCoordinator(
            settleDelayNanoseconds: 1_000_000_000,
            maxConcurrentJobs: 1
        )
        let recorder = WarmupRecorder()

        await coordinator.schedule(
            scope: "home.hero",
            settleDelayNanoseconds: 0,
            detailShell: {
                await recorder.record("hero")
            }
        )

        try await Task.sleep(nanoseconds: 80_000_000)

        let events = await recorder.events
        XCTAssertEqual(events, ["hero"])
    }

    private func sampleItems(count: Int) -> [MediaItem] {
        (0 ..< count).map { index in
            MediaItem(
                id: "item-\(index)",
                name: "Item \(index)",
                mediaType: index.isMultiple(of: 2) ? .movie : .series
            )
        }
    }
}

private actor WarmupRecorder {
    private(set) var events: [String] = []

    func record(_ value: String) {
        events.append(value)
    }
}
