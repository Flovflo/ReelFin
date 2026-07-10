import CoreGraphics
import PlaybackEngine
import XCTest
@testable import ReelFinUI

final class TVDetailActionButtonLayoutTests: XCTestCase {
    func testActivePlayerAlwaysVetoesGlobalTopNavigation() {
        XCTAssertFalse(TVTopNavigationPlayerVisibilityPolicy.isVisible(hasActivePlayer: true))
        XCTAssertTrue(TVTopNavigationPlayerVisibilityPolicy.isVisible(hasActivePlayer: false))
    }

    func testDeepCachedRecoveryNeverShowsMisleadingFullBufferOverlay() {
        XCTAssertFalse(
            CustomPlayerLaunchPresentationPolicy.showsInterruptionOverlay(
                phase: .buffering,
                reservoirSeconds: 503
            )
        )
        XCTAssertTrue(
            CustomPlayerLaunchPresentationPolicy.showsInterruptionOverlay(
                phase: .buffering,
                reservoirSeconds: 0.5
            )
        )
    }

    func testLaunchCopyDescribesOriginalQualityWithoutTechnicalCacheJargon() {
        XCTAssertEqual(
            CustomPlayerLaunchPresentationPolicy.statusText(
                phase: .prebuffering,
                progress: 0.4
            ),
            "Préparation de l’original · 40 %"
        )
    }

    func testNativeTVRemotePlayPauseIsRoutedToEngineExactlyOnce() {
        XCTAssertEqual(
            CustomPlayerTVRemoteRouting.action(for: .playPause),
            .togglePlayPause
        )
        XCTAssertEqual(CustomPlayerTVRemoteRouting.action(for: .menu), .exitPlayer)
        XCTAssertEqual(CustomPlayerTVRemoteRouting.action(for: .other), .system)
    }

    func testSkipIntroRequestsFocusWhenSuggestionAppears() {
        XCTAssertTrue(
            CustomPlayerSkipFocusPolicy.shouldRequestFocus(
                hadSuggestion: false,
                hasSuggestion: true
            )
        )
        XCTAssertFalse(
            CustomPlayerSkipFocusPolicy.shouldRequestFocus(
                hadSuggestion: true,
                hasSuggestion: true
            )
        )
    }

    func testHeroActionsUseOneFixedControlSize() {
        XCTAssertEqual(TVDetailActionButtonLayout.controlSize.width, 206)
        XCTAssertEqual(TVDetailActionButtonLayout.controlSize.height, 72)
        XCTAssertEqual(TVDetailActionButtonLayout.focusedScale, 1)
    }

    func testResumeChoiceFocusesContinueBeforeRestart() {
        XCTAssertEqual(PlaybackLaunchChoicePolicy.orderedChoices, [.resume, .restart])
        XCTAssertEqual(
            PlaybackLaunchChoicePolicy.title(for: .resume, resumeSeconds: 65),
            "Continuer à 1:05"
        )
        XCTAssertEqual(
            PlaybackLaunchChoicePolicy.title(for: .restart, resumeSeconds: 65),
            "Recommencer"
        )
    }

    func testResumeChoiceBackCommandCancelsWithoutStartingPlayback() {
        XCTAssertEqual(PlaybackLaunchChoicePolicy.exitCommandAction, .cancel)
    }

    func testCollapsedHeroChromeIsFullBleed() {
        let layout = TVDetailHeroChromeLayout(collapseProgress: 1)

        XCTAssertEqual(layout.outerHorizontalPadding, 0, accuracy: 0.001)
        XCTAssertEqual(layout.cornerRadius, 0, accuracy: 0.001)
        XCTAssertEqual(layout.strokeOpacity, 0, accuracy: 0.001)
    }

    func testRestingHeroChromeKeepsCinematicCardShape() {
        let layout = TVDetailHeroChromeLayout(collapseProgress: 0)

        XCTAssertEqual(layout.outerHorizontalPadding, 28, accuracy: 0.001)
        XCTAssertEqual(layout.cornerRadius, 44, accuracy: 0.001)
        XCTAssertGreaterThan(layout.strokeOpacity, 0)
    }

    func testInitialSeasonDefaultFocusWaitsForHeroFocus() {
        XCTAssertNil(
            TVDetailInitialFocusPolicy.seasonDefaultFocusID(
                selectedSeasonID: "season-5",
                firstSeasonID: "season-1",
                hasEstablishedPrimaryFocus: false
            )
        )
    }

    func testSeasonDefaultFocusUsesSelectionAfterHeroFocusIsEstablished() {
        XCTAssertEqual(
            TVDetailInitialFocusPolicy.seasonDefaultFocusID(
                selectedSeasonID: "season-5",
                firstSeasonID: "season-1",
                hasEstablishedPrimaryFocus: true
            ),
            "season-5"
        )
        XCTAssertEqual(
            TVDetailInitialFocusPolicy.seasonDefaultFocusID(
                selectedSeasonID: nil,
                firstSeasonID: "season-1",
                hasEstablishedPrimaryFocus: true
            ),
            "season-1"
        )
    }

    func testCompletedPresentationRequestsPrimaryFocusExactlyOnce() {
        XCTAssertTrue(
            TVDetailInitialFocusPolicy.shouldRequestPrimaryFocus(
                previousPresentationRequest: 0,
                newPresentationRequest: 1,
                hasEstablishedPrimaryFocus: false
            )
        )
        XCTAssertFalse(
            TVDetailInitialFocusPolicy.shouldRequestPrimaryFocus(
                previousPresentationRequest: 1,
                newPresentationRequest: 1,
                hasEstablishedPrimaryFocus: false
            )
        )
        XCTAssertFalse(
            TVDetailInitialFocusPolicy.shouldRequestPrimaryFocus(
                previousPresentationRequest: 0,
                newPresentationRequest: 1,
                hasEstablishedPrimaryFocus: true
            )
        )
    }
}
