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
        XCTAssertEqual(CustomPlayerTVRemoteRouting.action(for: .menu), .handleMenu)
        XCTAssertEqual(CustomPlayerTVRemoteRouting.action(for: .other), .ignore)
    }

    func testCustomPlayerOwnsAllTransportCommandsAndDisablesInlineAVKitChrome() {
        XCTAssertEqual(CustomPlayerTVRemoteRouting.action(for: .select), .toggleChrome)
        XCTAssertEqual(CustomPlayerTVRemoteRouting.action(for: .left), .seekRelative(-10))
        XCTAssertEqual(CustomPlayerTVRemoteRouting.action(for: .right), .seekRelative(30))
        XCTAssertFalse(CustomPlayerTVRemoteRouting.showsInlineAVKitControls)
    }

    func testPlayerMenuClosesPickerThenChromeThenPlayer() {
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

    func testPlayerSelectAndFocusReturnAreDeterministic() {
        XCTAssertEqual(NativePlayerTVRemoteControlPolicy.selectAction(chromeVisible: false), .showChrome)
        XCTAssertEqual(NativePlayerTVRemoteControlPolicy.selectAction(chromeVisible: true), .hideChrome)
        XCTAssertEqual(NativePlayerTVRemoteControlPolicy.nextFocusReturnToken(after: 41), 42)
    }

    func testPlayerTimelineRemoteSeeksClampAtTitleBounds() {
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

    func testPlayerChromeActionsHaveNoDeadVideoDestination() {
        XCTAssertEqual(NativePlayerTVChromeAction.allCases, [.subtitles, .audio, .video])
        XCTAssertEqual(NativePlayerTVChromeAction.audio.destination, .trackMenu(.audio))
        XCTAssertEqual(NativePlayerTVChromeAction.subtitles.destination, .trackMenu(.subtitles))
        XCTAssertEqual(NativePlayerTVChromeAction.video.destination, .videoPanel)
        XCTAssertEqual(NativePlayerTVChromeUtilityAction.info.destination, .playbackInfoPanel)
        XCTAssertEqual(NativePlayerTVChromeUtilityAction.insight.destination, .itemInsightPanel)
        XCTAssertEqual(NativePlayerTVChromeUtilityAction.continueWatching.destination, .continueWatching)
    }

    func testTVCommandDispatcherInvokesExactlyOneProductionCallbackPerCommand() {
        var selectCount = 0
        var playPauseCount = 0
        var moves: [NativePlayerRemoteMoveDirection] = []
        let dispatcher = NativePlayerTVCommandDispatcher(
            onSelect: { selectCount += 1 },
            onPlayPause: { playPauseCount += 1 },
            onMove: { moves.append($0) }
        )

        dispatcher.dispatch(.select)
        dispatcher.dispatch(.playPause)
        dispatcher.dispatch(.move(.left))

        XCTAssertEqual(selectCount, 1)
        XCTAssertEqual(playPauseCount, 1)
        XCTAssertEqual(moves, [.left])
    }

    func testTVFocusRestoresExactOriginatingActionAfterPanelDismissal() {
        XCTAssertEqual(NativePlayerTVChromeFocus.action(.audio), .audio)
        XCTAssertEqual(NativePlayerTVChromeFocus.action(.subtitles), .subtitles)
        XCTAssertEqual(NativePlayerTVChromeFocus.action(.video), .video)
        XCTAssertEqual(NativePlayerTVChromeFocus.utility(.info), .info)
        XCTAssertEqual(NativePlayerTVChromeFocus.utility(.insight), .insight)
        XCTAssertEqual(NativePlayerTVChromeFocus.utility(.continueWatching), .continueWatching)
    }

    func testExplicitChromeSuppressionIsTVOSOnly() {
        XCTAssertTrue(NativePlayerChromeExplicitVisibilityPolicy.canHideChrome(isTVOS: true))
        XCTAssertFalse(NativePlayerChromeExplicitVisibilityPolicy.canHideChrome(isTVOS: false))
    }

    func testTimelineAccessibilityValueInterpolatesSeconds() {
        XCTAssertEqual(
            NativePlayerTVTimelineAccessibility.value(
                playbackTime: 65.4,
                durationSeconds: 125.2
            ),
            "65 of 125 seconds"
        )
    }

    func testCustomAudioTrackModelCarriesAuthoritativeSelection() {
        XCTAssertEqual(
            CustomPlaybackAudioTrack(id: "fr", title: "Français", isSelected: true),
            CustomPlaybackAudioTrack(id: "fr", title: "Français", isSelected: true)
        )
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
        XCTAssertEqual(PlaybackLaunchChoicePolicy.defaultFocusedChoice, .resume)
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
