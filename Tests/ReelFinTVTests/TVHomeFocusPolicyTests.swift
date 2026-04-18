import Shared
@testable import ReelFinUI
import XCTest

final class TVHomeFocusPolicyTests: XCTestCase {
    func testEntryFocusDefaultsToHeroPlayWhenFeaturedExists() {
        let policy = TVHomeFocusPolicy(rows: sampleRows)

        let focusID = policy.entryFocusID(returnTarget: nil, hasFeaturedContent: true)

        XCTAssertEqual(focusID, TVHomeFocusPolicy.heroPlayFocusID)
    }

    func testEntryFocusRestoresRowItemWhenReturnTargetExists() {
        let policy = TVHomeFocusPolicy(rows: sampleRows)

        let focusID = policy.entryFocusID(
            returnTarget: .row(rowID: "row-b", itemID: "item-b2"),
            hasFeaturedContent: true
        )

        XCTAssertEqual(focusID, "item-b2")
    }

    func testMovingUpFromFirstRowTargetsHeroPlay() {
        let policy = TVHomeFocusPolicy(rows: sampleRows)

        let focusID = policy.targetFocusID(
            from: TVHomeRowFocusContext(rowID: "row-a", itemIndex: 1),
            direction: .up,
            hasFeaturedContent: true
        )

        XCTAssertEqual(focusID, TVHomeFocusPolicy.heroPlayFocusID)
    }

    func testMovingBetweenRowsPreservesNearestIndex() {
        let policy = TVHomeFocusPolicy(rows: sampleRows)

        let downFocusID = policy.targetFocusID(
            from: TVHomeRowFocusContext(rowID: "row-a", itemIndex: 2),
            direction: .down,
            hasFeaturedContent: true
        )
        let upFocusID = policy.targetFocusID(
            from: TVHomeRowFocusContext(rowID: "row-b", itemIndex: 2),
            direction: .up,
            hasFeaturedContent: true
        )

        XCTAssertEqual(downFocusID, "item-b2")
        XCTAssertEqual(upFocusID, "item-a2")
    }

    func testMovingDownFromLastRowHasNoTarget() {
        let policy = TVHomeFocusPolicy(rows: sampleRows)

        let focusID = policy.targetFocusID(
            from: TVHomeRowFocusContext(rowID: "row-b", itemIndex: 1),
            direction: .down,
            hasFeaturedContent: true
        )

        XCTAssertNil(focusID)
    }

    private var sampleRows: [HomeRow] {
        [
            HomeRow(
                id: "row-a",
                kind: .continueWatching,
                title: "Continue Watching",
                items: [
                    MediaItem(id: "item-a0", name: "A0", mediaType: .movie),
                    MediaItem(id: "item-a1", name: "A1", mediaType: .movie),
                    MediaItem(id: "item-a2", name: "A2", mediaType: .movie)
                ]
            ),
            HomeRow(
                id: "row-b",
                kind: .recentlyAddedMovies,
                title: "Recently Added",
                items: [
                    MediaItem(id: "item-b0", name: "B0", mediaType: .movie),
                    MediaItem(id: "item-b1", name: "B1", mediaType: .movie),
                    MediaItem(id: "item-b2", name: "B2", mediaType: .movie)
                ]
            )
        ]
    }
}
