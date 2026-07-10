import XCTest
@testable import ReelFinUI

final class NativePlayerChromeLayoutTests: XCTestCase {
    func testTVChromeExposesOnlyPlaybackMetadataActions() {
        XCTAssertEqual(
            NativePlayerTVChromeAction.allCases,
            [.audio, .subtitles, .video]
        )
        XCTAssertEqual(
            NativePlayerTVChromeAction.allCases.map(\.title),
            ["Audio", "Sous-titres", "Vidéo"]
        )

        let excludedTitles = ["Info", "InSight", "Continue Watching", "Accueil", "Recherche", "Bibliothèque"]
        XCTAssertTrue(
            Set(NativePlayerTVChromeAction.allCases.map(\.title))
                .isDisjoint(with: excludedTitles)
        )
    }

    func testOnlyTrackActionsOpenTheAnchoredTrackPopover() {
        XCTAssertEqual(NativePlayerTVChromeAction.audio.trackMenuKind, .audio)
        XCTAssertEqual(NativePlayerTVChromeAction.subtitles.trackMenuKind, .subtitles)
        XCTAssertNil(NativePlayerTVChromeAction.video.trackMenuKind)
    }

    func testTVChromeStaysCompactAndBottomAnchored() {
        let layout = NativePlayerTVChromeLayout.standard

        XCTAssertEqual(layout.alignment, .bottom)
        XCTAssertLessThanOrEqual(layout.gradientHeight, 520)
        XCTAssertGreaterThanOrEqual(layout.horizontalPadding, 64)
        XCTAssertLessThanOrEqual(layout.bottomPadding, 64)
        XCTAssertLessThanOrEqual(layout.timelineHeight, 8)
    }

    func testTVTrackPopoverUsesCompactRightSideMetrics() {
        let layout = NativePlayerTrackMenuLayout.tvOS

        XCTAssertLessThanOrEqual(layout.panelWidth, 560)
        XCTAssertLessThanOrEqual(layout.contentMaxHeight, 480)
        XCTAssertLessThanOrEqual(layout.cornerRadius, 42)
    }
}
