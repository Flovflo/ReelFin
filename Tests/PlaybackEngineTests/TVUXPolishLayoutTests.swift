import XCTest
import UIKit
@testable import ReelFinUI

final class TVUXPolishLayoutTests: XCTestCase {
    @MainActor
    func testPlayerAccessibilityEvidenceContainerMirrorsTransientLaunchStates() {
        let container = PlayerAccessibilityEvidenceContainerView()

        update(
            container,
            showsLaunchPreparation: true,
            showsBuffering: false
        )
        XCTAssertTrue(marker("custom_player_launch_preparation", existsIn: container))
        XCTAssertFalse(marker("custom_player_buffering", existsIn: container))

        update(
            container,
            showsLaunchPreparation: false,
            showsBuffering: true
        )
        XCTAssertFalse(marker("custom_player_launch_preparation", existsIn: container))
        XCTAssertTrue(marker("custom_player_buffering", existsIn: container))
    }

    func testCompactResumeChoiceMetrics() {
        let layout = TVPlaybackResumeChoiceLayout.standard
        XCTAssertEqual(layout.maxWidth, 760)
        XCTAssertEqual(layout.cornerRadius, 34)
        XCTAssertEqual(layout.horizontalPadding, 44)
        XCTAssertEqual(layout.verticalPadding, 34)
        XCTAssertEqual(layout.buttonHeight, 66)
        XCTAssertEqual(layout.focusOpacity, 0.20)
        XCTAssertEqual(layout.buttonSpacing, 16)
        XCTAssertEqual(layout.questionFontSize, 32)
        XCTAssertEqual(layout.buttonHorizontalPadding, 16)
        XCTAssertEqual(layout.buttonFontSize, 22)
        XCTAssertEqual(layout.buttonTitleLineLimit, 1)
        XCTAssertTrue(layout.buttonTitleAllowsTightening)
        XCTAssertEqual(layout.buttonTitleMinimumScaleFactor, 0.82)
    }

    func testCompleteResumeChoicePolicyTitlesFitAvailableButtonWidth() {
        let layout = TVPlaybackResumeChoiceLayout.standard
        let font = UIFont.systemFont(ofSize: layout.buttonFontSize, weight: .semibold)
        let titles = PlaybackLaunchChoicePolicy.orderedChoices.map {
            PlaybackLaunchChoicePolicy.title(for: $0, resumeSeconds: 359_999)
        }

        XCTAssertEqual(titles, ["Continuer à 99:59:59", "Recommencer"])
        for title in titles {
            let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(
                textWidth + layout.buttonIconAndSpacingWidth,
                layout.availableButtonContentWidth,
                "The complete policy title \(title) must fit without ellipsis."
            )
        }
    }

    func testCompactPlayerLaunchMetrics() {
        let layout = TVPlayerLaunchLayout.standard
        XCTAssertEqual(layout.maxWidth, 420)
        XCTAssertEqual(layout.cornerRadius, 24)
        XCTAssertEqual(layout.spinnerSize, 34)
        XCTAssertEqual(layout.progressWidth, 280)
        XCTAssertEqual(layout.screenInset, 64)
        XCTAssertEqual(layout.statusLineLimit, 2)
    }

    func testTVFocusScalesMatchApprovedCouchDistanceGeometry() {
        XCTAssertEqual(TVFocusGeometry.scale(for: .homePosterCard, reduceMotion: false), 1.09)
        XCTAssertEqual(TVFocusGeometry.scale(for: .homeLandscapeCard, reduceMotion: false), 1.08)
        XCTAssertEqual(TVFocusGeometry.scale(for: .libraryPoster, reduceMotion: false), 1.09)
        XCTAssertEqual(TVFocusGeometry.scale(for: .episodeCard, reduceMotion: false), 1.05)
        XCTAssertEqual(TVFocusGeometry.scale(for: .homePosterCard, reduceMotion: true), 1.02)
        XCTAssertEqual(TVFocusGeometry.libraryActivationScale, 1.025)
    }

    func testTVFocusMotionHasNoBounceOrWiggle() {
        XCTAssertEqual(TVFocusAnimationMetrics.normalDuration, 0.16)
        XCTAssertEqual(TVFocusAnimationMetrics.normalBounce, 0)
        XCTAssertEqual(TVFocusAnimationMetrics.reducedMotionDuration, 0.18)
    }

    func testReduceMotionDoesNotRaiseNavigationRoleAboveItsNormalScale() {
        XCTAssertEqual(TVFocusGeometry.scale(for: .navItem, reduceMotion: true), 1.0)
    }

    func testLibraryFirstRowReserveContainsScaleOverflowAndShadow() {
        let reserve = TVLibraryFocusLayout.firstRowTopReserve(
            cardWidth: 240,
            scale: 1.09,
            minimumReserve: 34
        )
        XCTAssertGreaterThanOrEqual(reserve, 34 + ((240 * 1.09 - 240) / 2))
    }

    func testTVTopNavigationKeepsSearchInAnIndependentGlassSurface() {
        XCTAssertEqual(TVTopNavigationLayout.primaryDestinations, [.watchNow, .library])
        XCTAssertEqual(TVTopNavigationLayout.isolatedDestination, .search)
    }

    @MainActor
    private func update(
        _ container: PlayerAccessibilityEvidenceContainerView,
        showsLaunchPreparation: Bool,
        showsBuffering: Bool
    ) {
        container.update(
            playbackTime: 0,
            transportState: .buffering,
            videoRenderingReady: false,
            audioRenderingReady: false,
            audioEvidenceRoute: nil,
            isAdvancing: false,
            completedSeekTarget: nil,
            didCompleteSeekToZero: false,
            readerGeneration: nil,
            errorMessage: nil,
            showsLaunchPreparation: showsLaunchPreparation,
            showsBuffering: showsBuffering
        )
    }

    @MainActor
    private func marker(
        _ identifier: String,
        existsIn container: PlayerAccessibilityEvidenceContainerView
    ) -> Bool {
        container.subviews.contains { $0.accessibilityIdentifier == identifier }
    }
}
