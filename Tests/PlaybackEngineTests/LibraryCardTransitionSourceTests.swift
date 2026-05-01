@testable import ReelFinUI
import XCTest

final class LibraryCardTransitionSourceTests: XCTestCase {
    func testTransitionSourceIsScopedToLibrary() {
        XCTAssertEqual(
            LibraryCardTransitionSource.id(itemID: "zootopia-2"),
            "library::zootopia-2"
        )
    }
}
