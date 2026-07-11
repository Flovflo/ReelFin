import XCTest
@testable import ReelFinUI

final class NativePlayerChromeLayoutTests: XCTestCase {
    func testCustomRemoteCommandsAreOwnedByReelFinExactlyOnce() {
        XCTAssertEqual(CustomPlayerTVRemoteRouting.action(for: .playPause), .togglePlayPause)
        XCTAssertEqual(CustomPlayerTVRemoteRouting.action(for: .select), .toggleChrome)
        XCTAssertEqual(CustomPlayerTVRemoteRouting.action(for: .left), .seekRelative(-10))
        XCTAssertEqual(CustomPlayerTVRemoteRouting.action(for: .right), .seekRelative(30))
        XCTAssertEqual(CustomPlayerTVRemoteRouting.action(for: .menu), .handleMenu)
        XCTAssertEqual(CustomPlayerTVRemoteRouting.action(for: .other), .ignore)
        XCTAssertFalse(CustomPlayerTVRemoteRouting.showsInlineAVKitControls)
    }

    func testTVMenuPrecedenceClosesPickerThenChromeThenPlayer() {
        XCTAssertEqual(
            NativePlayerTVRemoteControlPolicy.menuAction(chromeVisible: true, pickerVisible: true),
            .dismissPicker
        )
        XCTAssertEqual(
            NativePlayerTVRemoteControlPolicy.menuAction(chromeVisible: true, pickerVisible: false),
            .hideChrome
        )
        XCTAssertEqual(
            NativePlayerTVRemoteControlPolicy.menuAction(chromeVisible: false, pickerVisible: false),
            .exitPlayer
        )
    }

    func testTVSelectAndFocusReturnAreDeterministic() {
        XCTAssertEqual(NativePlayerTVRemoteControlPolicy.selectAction(chromeVisible: false), .showChrome)
        XCTAssertEqual(NativePlayerTVRemoteControlPolicy.selectAction(chromeVisible: true), .hideChrome)
        XCTAssertEqual(NativePlayerTVRemoteControlPolicy.nextFocusReturnToken(after: 41), 42)
    }

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
        XCTAssertEqual(NativePlayerTVChromeAction.video.destination, .videoPanel)
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

    func testTVTimelineRemoteSeeksAreUsefulAndClamped() {
        XCTAssertEqual(
            NativePlayerRemoteControlPolicy.clampedSeekTarget(
                from: 8,
                delta: NativePlayerRemoteControlPolicy.rewindSeconds,
                durationSeconds: 120
            ),
            0
        )
        XCTAssertEqual(
            NativePlayerRemoteControlPolicy.clampedSeekTarget(
                from: 110,
                delta: NativePlayerRemoteControlPolicy.fastForwardSeconds,
                durationSeconds: 120
            ),
            120
        )
    }
}
