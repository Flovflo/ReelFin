import XCTest
@testable import ReelFinUI

final class TVAuthNavigationPolicyTests: XCTestCase {
    func testDeckClampsInitialPageAndCompletesOnlyAtLastPage() {
        var deck = TVOnboardingDeckState(initialIndex: 99, count: 4)
        XCTAssertEqual(deck.index, 3)
        XCTAssertEqual(deck.advance(), .completed)
    }

    func testDeckAdvancesAndRetreatsWithoutCrossingBounds() {
        var deck = TVOnboardingDeckState(initialIndex: 0, count: 4)
        XCTAssertEqual(deck.advance(), .advanced)
        XCTAssertEqual(deck.index, 1)
        XCTAssertTrue(deck.retreat())
        XCTAssertEqual(deck.index, 0)
        XCTAssertFalse(deck.retreat())
    }

    func testEveryInteractiveLoginPhaseHasRouteSpecificPreferredFocus() {
        XCTAssertEqual(TVLoginNavigationPolicy.preferredFocus(for: .landing), .landingQuickConnect)
        XCTAssertEqual(TVLoginNavigationPolicy.preferredFocus(for: .server), .serverAddress)
        XCTAssertEqual(TVLoginNavigationPolicy.preferredFocus(for: .credentials), .credentialsUsername)
        XCTAssertEqual(TVLoginNavigationPolicy.preferredFocus(for: .quickConnect), .quickConnectUsePassword)
        XCTAssertNil(TVLoginNavigationPolicy.preferredFocus(for: .submitting))
        XCTAssertNil(TVLoginNavigationPolicy.preferredFocus(for: .success))
    }

    func testBackDestinationsRespectQuickConnectOrigin() {
        XCTAssertEqual(TVLoginNavigationPolicy.backDestination(from: .server, quickConnectOrigin: .landing), .landing)
        XCTAssertEqual(TVLoginNavigationPolicy.backDestination(from: .credentials, quickConnectOrigin: .landing), .server)
        XCTAssertEqual(TVLoginNavigationPolicy.backDestination(from: .quickConnect, quickConnectOrigin: .landing), .landing)
        XCTAssertEqual(TVLoginNavigationPolicy.backDestination(from: .quickConnect, quickConnectOrigin: .server), .server)
        XCTAssertNil(TVLoginNavigationPolicy.backDestination(from: .landing, quickConnectOrigin: .landing))
    }
}
