import Shared
@testable import ReelFinUI
import XCTest

@MainActor
final class HomeViewModelFeedEnrichmentTests: XCTestCase {
    func testLoadKeepsAllRowsWhilePartialEnrichmentRuns() async throws {
        let dependencies = ReelFinPreviewFactory.dependencies()
        let expectedFeed = try await dependencies.repository.fetchHomeFeed()
        XCTAssertGreaterThan(expectedFeed.rows.count, 3)

        let viewModel = HomeViewModel(dependencies: dependencies)
        await viewModel.load()

        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(viewModel.feed.rows.map(\.id), expectedFeed.rows.map(\.id))
        XCTAssertEqual(viewModel.feed.rows.count, expectedFeed.rows.count)
    }
}
