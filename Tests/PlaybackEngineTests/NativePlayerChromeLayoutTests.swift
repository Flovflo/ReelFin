import XCTest
@testable import ReelFinUI

final class NativePlayerChromeLayoutTests: XCTestCase {
    func testPlaybackEvidenceRequiresTwoAdvancingObservationsAndResetsAtSessionBoundaries() {
        var evidence = PlayerAccessibilityEvidenceState()

        evidence.observe(playbackTime: 8, generation: 1)
        XCTAssertFalse(evidence.isAdvancing)
        evidence.observe(playbackTime: 8.6, generation: 1)
        XCTAssertFalse(evidence.isAdvancing)
        evidence.observe(playbackTime: 9.2, generation: 1)
        XCTAssertTrue(evidence.isAdvancing)

        evidence.beginSeek(target: 0)
        XCTAssertFalse(evidence.isAdvancing)
        XCTAssertFalse(evidence.didCompleteSeek)
        evidence.observe(playbackTime: 0.1, generation: 2)
        XCTAssertTrue(evidence.didCompleteSeek)
        XCTAssertTrue(evidence.didCompleteSeekToZero)
        XCTAssertEqual(evidence.readerGeneration, 2)

        evidence.reset()
        XCTAssertFalse(evidence.isAdvancing)
        XCTAssertFalse(evidence.didCompleteSeek)
        XCTAssertNil(evidence.readerGeneration)
    }

    func testNativeRendererEvidenceRequiresAcceptedSamplesRatherThanTrackMetadata() {
        let metadataOnly = NativePlayerAccessibilityDiagnostics(
            rows: [
                "state=buffering",
                "audioDecoderBackend=AppleAudioToolbox",
                "rendererBackend=AVSampleBufferDisplayLayer(compressed)",
                "audioRendererBackend=AVSampleBufferAudioRenderer(compressed)"
            ]
        )
        XCTAssertFalse(metadataOnly.videoRenderingReady)
        XCTAssertFalse(metadataOnly.audioRenderingReady)

        let rendered = NativePlayerAccessibilityDiagnostics(
            rows: [
                "state=playing",
                "primed video=2 audio=3",
                "audioSamples rendered=2048 maxPerBuffer=1024"
            ]
        )
        XCTAssertEqual(rendered.transportState, .playing)
        XCTAssertTrue(rendered.videoRenderingReady)
        XCTAssertTrue(rendered.audioRenderingReady)
    }

    func testAccessibilityGenerationValueContainsNoMediaIdentity() {
        var evidence = PlayerAccessibilityEvidenceState()
        evidence.observe(playbackTime: 1, generation: 42)

        XCTAssertEqual(evidence.readerGenerationValue, "42")
        XCTAssertFalse(evidence.readerGenerationValue?.contains("/") == true)
        XCTAssertFalse(evidence.readerGenerationValue?.contains("?") == true)
    }

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

    func testTVChromeExposesReferenceOrderedCircularPlaybackActions() {
        XCTAssertEqual(
            NativePlayerTVChromeAction.allCases,
            [.subtitles, .audio, .video]
        )
        XCTAssertEqual(
            NativePlayerTVChromeAction.allCases.map(\.title),
            ["Sous-titres", "Audio", "Vidéo"]
        )
        XCTAssertTrue(NativePlayerTVChromeAction.allCases.allSatisfy { $0.controlShape == .circle })
        XCTAssertTrue(NativePlayerTVChromeAction.allCases.allSatisfy { !$0.accessibilityIdentifier.isEmpty })
    }

    func testOnlyTrackActionsOpenTheAnchoredTrackPopover() {
        XCTAssertEqual(NativePlayerTVChromeAction.audio.trackMenuKind, .audio)
        XCTAssertEqual(NativePlayerTVChromeAction.subtitles.trackMenuKind, .subtitles)
        XCTAssertNil(NativePlayerTVChromeAction.video.trackMenuKind)
        XCTAssertEqual(NativePlayerTVChromeAction.video.destination, .videoPanel)
    }

    func testTVChromeMatchesReferenceNormalizedGeometry() {
        let layout = NativePlayerTVChromeLayout.standard

        XCTAssertEqual(layout.alignment, .bottom)
        XCTAssertEqual(layout.referenceSize.width, 1_920)
        XCTAssertEqual(layout.referenceSize.height, 1_080)
        XCTAssertEqual(layout.gradientHeight / layout.referenceSize.height, 1.0 / 3.0, accuracy: 0.01)
        XCTAssertEqual(layout.horizontalPadding / layout.referenceSize.width, 1.0 / 24.0, accuracy: 0.002)
        XCTAssertEqual(layout.circleDiameter / layout.referenceSize.height, 70.0 / 1_080.0, accuracy: 0.002)
        XCTAssertEqual(layout.timelineY / layout.referenceSize.height, 900.0 / 1_080.0, accuracy: 0.015)
        XCTAssertEqual(layout.utilityRowY / layout.referenceSize.height, 985.0 / 1_080.0, accuracy: 0.015)
        XCTAssertGreaterThanOrEqual(layout.titleMinimumScaleFactor, 0.55)
        XCTAssertLessThanOrEqual(layout.maximumTitleWidthRatio, 0.70)
        XCTAssertLessThanOrEqual(layout.timelineHeight, 8)
    }

    func testTVChromeUtilityPillsAreFunctionalAndReferenceOrdered() {
        XCTAssertEqual(
            NativePlayerTVChromeUtilityAction.allCases,
            [.info, .insight, .continueWatching]
        )
        XCTAssertEqual(
            NativePlayerTVChromeUtilityAction.allCases.map(\.title),
            ["Info", "InSight", "Continue Watching"]
        )
        XCTAssertEqual(NativePlayerTVChromeUtilityAction.info.destination, .playbackInfoPanel)
        XCTAssertEqual(NativePlayerTVChromeUtilityAction.insight.destination, .itemInsightPanel)
        XCTAssertEqual(NativePlayerTVChromeUtilityAction.continueWatching.destination, .continueWatching)
        XCTAssertTrue(NativePlayerTVChromeUtilityAction.allCases.allSatisfy { $0.controlShape == .capsule })
        XCTAssertTrue(NativePlayerTVChromeUtilityAction.allCases.allSatisfy { !$0.accessibilityIdentifier.isEmpty })
    }

    func testTVChromeFocusCoversEveryCircularAndUtilityAction() {
        XCTAssertEqual(NativePlayerTVChromeFocus.action(.subtitles), .subtitles)
        XCTAssertEqual(NativePlayerTVChromeFocus.action(.audio), .audio)
        XCTAssertEqual(NativePlayerTVChromeFocus.action(.video), .video)
        XCTAssertEqual(NativePlayerTVChromeFocus.utility(.info), .info)
        XCTAssertEqual(NativePlayerTVChromeFocus.utility(.insight), .insight)
        XCTAssertEqual(NativePlayerTVChromeFocus.utility(.continueWatching), .continueWatching)
    }

    func testCurrentTimeLabelTracksPlayheadWithoutCollidingWithEdges() {
        XCTAssertEqual(
            NativePlayerTVTimelineLabelLayout.currentCenterX(progress: 0.25, width: 1_760),
            440,
            accuracy: 0.001
        )
        XCTAssertEqual(
            NativePlayerTVTimelineLabelLayout.currentCenterX(progress: 0, width: 1_760),
            48,
            accuracy: 0.001
        )
        XCTAssertEqual(
            NativePlayerTVTimelineLabelLayout.currentCenterX(progress: 1, width: 1_760),
            1_580,
            accuracy: 0.001
        )
    }

    func testContinueWatchingOnlyResumesPausedPlaybackBeforeHidingChrome() {
        XCTAssertTrue(NativePlayerTVContinueWatchingPolicy.shouldResume(isPaused: true))
        XCTAssertFalse(NativePlayerTVContinueWatchingPolicy.shouldResume(isPaused: false))
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
