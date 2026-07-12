import XCTest
@testable import ReelFinUI

final class TVUXPolishNavigationTests: XCTestCase {
    func testDetailBackIsConsumedUntilClosingCompletes() {
        var state = TVDetailPresentationCoordinator()
        state.beginOpening(itemID: "dexter", sourceID: "home-row-dexter")
        state.finishOpening()

        XCTAssertEqual(state.handleBack(), .beginClosing)
        XCTAssertEqual(state.handleBack(), .consumedWhileClosing)
        XCTAssertTrue(state.keepsDetailMounted)

        state.finishClosing()

        XCTAssertEqual(state.phase, .idle)
    }

    func testBackPrecedenceReturnsInsideAppBeforeSystemExit() {
        XCTAssertEqual(TVBackNavigationPolicy.action(for: .resumeChoice), .cancelResumeChoice)
        XCTAssertEqual(TVBackNavigationPolicy.action(for: .playerPanel), .closePlayerPanel)
        XCTAssertEqual(TVBackNavigationPolicy.action(for: .player), .closePlayer)
        XCTAssertEqual(TVBackNavigationPolicy.action(for: .detail), .closeDetail)
        XCTAssertEqual(TVBackNavigationPolicy.action(for: .root), .allowSystemExit)
    }

    func testInvalidPresentationTransitionsAreIgnored() {
        var state = TVDetailPresentationCoordinator()

        state.finishOpening()
        state.finishClosing()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.handleBack(), .allowRoot)

        state.beginOpening(itemID: "dexter", sourceID: nil)
        state.beginOpening(itemID: "other", sourceID: "other-source")
        XCTAssertEqual(state.phase, .opening(itemID: "dexter", sourceID: nil))

        state.finishClosing()
        XCTAssertEqual(state.phase, .opening(itemID: "dexter", sourceID: nil))
    }

    func testDetailTransitionMetricsUseSpecifiedDurations() {
        XCTAssertEqual(TVDetailTransitionMetrics.openingDuration, 0.34)
        XCTAssertEqual(TVDetailTransitionMetrics.closingDuration, 0.30)
        XCTAssertEqual(TVDetailTransitionMetrics.reducedMotionDuration, 0.18)
    }
}
