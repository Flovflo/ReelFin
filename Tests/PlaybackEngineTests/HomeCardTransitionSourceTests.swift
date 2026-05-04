@testable import ReelFinUI
import XCTest

final class HomeCardTransitionSourceTests: XCTestCase {
    func testTransitionSourceIncludesRowIDForDuplicateItems() {
        let itemID = "zootopia-2"

        let continueWatchingSource = HomeCardTransitionSource.id(
            rowID: "continue-watching",
            itemID: itemID
        )
        let recentlyReleasedSource = HomeCardTransitionSource.id(
            rowID: "recently-released-movies",
            itemID: itemID
        )

        XCTAssertNotEqual(continueWatchingSource, recentlyReleasedSource)
        XCTAssertEqual(continueWatchingSource, "continue-watching::zootopia-2")
    }

    func testTransitionSourceCanIncludeLoopOccurrence() {
        XCTAssertEqual(
            HomeCardTransitionSource.id(
                rowID: "recently-released-movies",
                itemID: "zootopia-2",
                occurrenceID: "cycle-4-index-1"
            ),
            "recently-released-movies::cycle-4-index-1::zootopia-2"
        )
    }

    func testFeaturedTransitionSourceIsScopedToHero() {
        XCTAssertEqual(
            HomeFeaturedTransitionSource.id(itemID: "what-now"),
            "featured::what-now"
        )
    }
}
