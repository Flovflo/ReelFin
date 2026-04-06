import Shared
import XCTest

final class HomeRowIdentityTests: XCTestCase {
    func testDefaultIdentifierIsStableForSameSectionAndTitle() {
        let first = HomeRow(kind: .continueWatching, title: "Continue Watching", items: [])
        let second = HomeRow(kind: .continueWatching, title: "Continue Watching", items: [])

        XCTAssertEqual(first.id, second.id)
    }

    func testExplicitIdentifierStillWins() {
        let row = HomeRow(id: "custom-row", kind: .popular, title: "Popular", items: [])

        XCTAssertEqual(row.id, "custom-row")
    }
}
