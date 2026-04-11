import Shared
@testable import ReelFinUI
import XCTest

@MainActor
final class HomeViewModelFeedEnrichmentTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "home.sectionPreferences.v3")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "home.sectionPreferences.v3")
        super.tearDown()
    }

    func testLoadShowsOnlySupportedHomeSections() async throws {
        let dependencies = ReelFinPreviewFactory.dependencies()
        let expectedFeed = try await dependencies.repository.fetchHomeFeed()

        let viewModel = HomeViewModel(dependencies: dependencies)
        await viewModel.load()

        XCTAssertEqual(
            expectedFeed.rows.map(\.kind),
            [.continueWatching, .recentlyReleasedMovies, .recentlyReleasedSeries, .recentlyAddedMovies, .recentlyAddedSeries]
        )
        XCTAssertEqual(
            viewModel.visibleRows.map(\.kind),
            [.continueWatching, .recentlyReleasedMovies, .recentlyReleasedSeries, .recentlyAddedMovies, .recentlyAddedSeries]
        )
        XCTAssertEqual(
            viewModel.sectionCustomizationKinds,
            [.continueWatching, .recentlyReleasedMovies, .recentlyReleasedSeries, .recentlyAddedMovies, .recentlyAddedSeries]
        )
        XCTAssertEqual(
            viewModel.visibleRows.map(\.title),
            ["Continue Watching", "Recently Released Movies", "Recently Released TV Shows", "Recently Added Movies", "Recently Added TV"]
        )
    }
}
