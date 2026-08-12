@testable import ReelFinUI
import XCTest

final class StorefrontDeterminismTests: XCTestCase {
    func testStableSeedHashHasHandCheckedFNV1aValues() {
        XCTAssertEqual(StorefrontStableSeed.hash(""), 14_695_981_039_346_656_037)
        XCTAssertEqual(StorefrontStableSeed.hash("ReelFin"), 17_809_080_437_298_695_942)
    }

    func testPaletteIndexIsStableAndBounded() {
        XCTAssertEqual(StorefrontStableSeed.paletteIndex(for: "ReelFin", paletteCount: 4), 2)
        XCTAssertEqual(StorefrontStableSeed.paletteIndex(for: "ReelFin", paletteCount: 1), 0)
    }
}
