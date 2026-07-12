import XCTest
import PlaybackEngine
import Shared
@testable import ReelFinUI

final class NativePlayerChromeLayoutTests: XCTestCase {
    func testIOSSubtitlePresentationIsCompactWhileTVRemainsReadable() {
        let ios = CustomPlayerSubtitlePresentationPolicy.style(for: .iOS)
        let tv = CustomPlayerSubtitlePresentationPolicy.style(for: .tvOS)

        XCTAssertEqual(ios.fontSize, 20)
        XCTAssertLessThanOrEqual(ios.fontSize, 24)
        XCTAssertEqual(ios.maximumLineCount, 2)
        XCTAssertEqual(ios.maximumWidthRatio, 0.85, accuracy: 0.001)
        XCTAssertEqual(ios.horizontalPadding, 10)
        XCTAssertEqual(ios.verticalPadding, 4)
        XCTAssertEqual(ios.backgroundOpacity, 0.30, accuracy: 0.001)

        XCTAssertEqual(tv.fontSize, 34)
        XCTAssertEqual(tv.maximumLineCount, 0)
        XCTAssertGreaterThan(tv.fontSize, ios.fontSize)
    }

    func testIOSSubtitleControlUsesSystemBottomChromeWithoutFloatingDuplicate() {
        XCTAssertFalse(CustomPlayerIOSSubtitleControlPolicy.showsFloatingPicker)
        XCTAssertTrue(CustomPlayerIOSSubtitleControlPolicy.usesSystemBottomControl)
    }

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

    func testPlaybackEvidenceExpiresWhenPausedOrSamplesFreeze() {
        var evidence = PlayerAccessibilityEvidenceState()

        evidence.observe(playbackTime: 8, generation: 1, transportState: .playing, observedAt: 10)
        evidence.observe(playbackTime: 8.6, generation: 1, transportState: .playing, observedAt: 11)
        evidence.observe(playbackTime: 9.2, generation: 1, transportState: .playing, observedAt: 12)
        XCTAssertTrue(evidence.isAdvancing)

        evidence.setTransportState(.paused)
        XCTAssertFalse(evidence.isAdvancing)

        evidence.observe(playbackTime: 10, generation: 1, transportState: .playing, observedAt: 20)
        evidence.observe(playbackTime: 10.6, generation: 1, transportState: .playing, observedAt: 21)
        evidence.observe(playbackTime: 11.2, generation: 1, transportState: .playing, observedAt: 22)
        XCTAssertTrue(evidence.isAdvancing)
        evidence.expireAdvancing(observedAt: 25)
        XCTAssertFalse(evidence.isAdvancing)
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

        let packetMetadataOnly = NativePlayerAccessibilityDiagnostics(
            rows: ["state=playing", "packets video=5 audio=9"]
        )
        XCTAssertTrue(packetMetadataOnly.videoRenderingReady)
        XCTAssertFalse(packetMetadataOnly.audioRenderingReady)
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
        XCTAssertEqual(layout.bottomPadding / layout.referenceSize.height, 50.0 / 1_080.0, accuracy: 0.005)
        XCTAssertEqual(layout.circleDiameter / layout.referenceSize.height, 70.0 / 1_080.0, accuracy: 0.002)
        XCTAssertEqual(layout.timelineY / layout.referenceSize.height, 900.0 / 1_080.0, accuracy: 0.015)
        XCTAssertEqual(layout.utilityRowY / layout.referenceSize.height, 985.0 / 1_080.0, accuracy: 0.015)
        XCTAssertGreaterThanOrEqual(layout.titleMinimumScaleFactor, 0.55)
        XCTAssertLessThanOrEqual(layout.maximumTitleWidthRatio, 0.70)
        XCTAssertLessThanOrEqual(layout.timelineHeight, 8)
    }

    func testTVChromeUsesReferenceRegularInteractiveLiquidGlassWithWhiteFocus() {
        let layout = NativePlayerTVChromeLayout.standard
        let style = NativePlayerTVChromeGlassStyle.standard

        XCTAssertEqual(layout.circleDiameter, 70)
        XCTAssertEqual(layout.utilityHeight, 64)
        XCTAssertEqual(layout.iconSize, 28)
        XCTAssertEqual(style.variant, .regular)
        XCTAssertTrue(style.isInteractive)
        XCTAssertEqual(style.opaqueFillOpacity, 0)
        XCTAssertGreaterThanOrEqual(style.focusedFillOpacity, 0.32)
        XCTAssertLessThanOrEqual(style.focusedFillOpacity, 0.42)
        XCTAssertLessThanOrEqual(style.unfocusedStrokeOpacity, 0.10)
        XCTAssertEqual(style.focusedScale, 1)
    }

    func testTVChromeUtilityPillsAreFunctionalAndReferenceOrdered() {
        XCTAssertEqual(
            NativePlayerTVChromeUtilityAction.allCases,
            [.info, .insight, .continueWatching]
        )
        XCTAssertEqual(
            NativePlayerTVChromeUtilityAction.allCases.map(\.title),
            ["Info", "Détails", "Continuer"]
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

    func testAVKitSubtitleRootMatchesReferenceHierarchy() {
        XCTAssertEqual(
            NativePlayerAVKitMenuPage.subtitlesRoot.rowIDs,
            [.subtitleOn, .subtitleOff, .subtitleLanguage, .subtitleStyle]
        )
    }

    func testAVKitMenuLayoutMatchesApprovedReferenceMetrics() {
        let layout = NativePlayerAVKitMenuLayout.standard

        XCTAssertEqual(layout.width, 600)
        XCTAssertEqual(layout.cornerRadius, 44)
        XCTAssertEqual(layout.horizontalInset, 54)
        XCTAssertEqual(layout.verticalInset, 42)
        XCTAssertEqual(layout.headerSize, 30)
        XCTAssertEqual(layout.primarySize, 34)
        XCTAssertEqual(layout.secondarySize, 22)
        XCTAssertEqual(layout.choiceHeight, 68)
        XCTAssertEqual(layout.navigationHeight, 108)
        XCTAssertLessThanOrEqual(layout.focusOpacity, 0.22)
        XCTAssertEqual(layout.selectedOpacity, 0.045)
        XCTAssertEqual(layout.opaqueBackgroundOpacity, 0)
    }

    func testEveryReferenceRowMapsToARealAction() {
        XCTAssertEqual(NativePlayerAVKitMenuAction.forRow(.subtitleOn), .enableSubtitles)
        XCTAssertEqual(NativePlayerAVKitMenuAction.forRow(.subtitleOff), .disableSubtitles)
        XCTAssertEqual(NativePlayerAVKitMenuAction.forRow(.subtitleLanguage), .openLanguages)
        XCTAssertEqual(NativePlayerAVKitMenuAction.forRow(.subtitleStyle), .openStyles)
    }

    func testAVKitMenuActionMappingPreservesAssociatedPayloads() {
        XCTAssertEqual(NativePlayerAVKitMenuAction.forRow(.audio("fr")), .selectAudio("fr"))
        XCTAssertEqual(
            NativePlayerAVKitMenuAction.forRow(.subtitleTrack("forced-fr")),
            .selectSubtitle("forced-fr")
        )
        XCTAssertEqual(
            NativePlayerAVKitMenuAction.forRow(.style(.subtle)),
            .selectStyle(.subtle)
        )
    }

    func testAVKitMenuReplicaIsLimitedToTVOS() {
        XCTAssertFalse(NativePlayerAVKitMenuPresentationPolicy.usesReplica(on: .iOS))
        XCTAssertTrue(NativePlayerAVKitMenuPresentationPolicy.usesReplica(on: .tvOS))
    }

    func testAVKitMenuNavigationReturnsSubmenuThenDismissesRoot() {
        var state = NativePlayerAVKitMenuState(page: .subtitlesRoot)

        state.perform(.openLanguages)

        XCTAssertEqual(state.page, .subtitleLanguages)
        XCTAssertEqual(state.handleMenu(), .returnedToRoot)
        XCTAssertEqual(state.page, .subtitlesRoot)
        XCTAssertEqual(state.focusedRow, .subtitleLanguage)
        XCTAssertEqual(state.handleMenu(), .dismissed)
    }

    func testAVKitMenuLeftReturnsEachSubmenuWithoutDismissingRoot() {
        var languageState = NativePlayerAVKitMenuState(page: .subtitleLanguages)
        var styleState = NativePlayerAVKitMenuState(page: .subtitleStyles)
        var rootState = NativePlayerAVKitMenuState(page: .subtitlesRoot)

        XCTAssertTrue(languageState.handleLeft())
        XCTAssertEqual(languageState.page, .subtitlesRoot)
        XCTAssertEqual(languageState.focusedRow, .subtitleLanguage)
        XCTAssertTrue(styleState.handleLeft())
        XCTAssertEqual(styleState.page, .subtitlesRoot)
        XCTAssertEqual(styleState.focusedRow, .subtitleStyle)
        XCTAssertFalse(rootState.handleLeft())
        XCTAssertEqual(rootState.page, .subtitlesRoot)
    }

    func testAudioAndSubtitleSelectionDispatchExactlyOnce() {
        var selections: [PlaybackControlSelection] = []

        NativePlayerAVKitMenuDispatch.dispatch(.audio("fr"), to: { selections.append($0) })
        NativePlayerAVKitMenuDispatch.dispatch(.subtitle("forced-fr"), to: { selections.append($0) })

        XCTAssertEqual(selections.count, 2)
        guard case let .audio(audioID) = selections[0],
              case let .subtitle(subtitleID) = selections[1] else {
            return XCTFail("Expected one audio selection followed by one subtitle selection")
        }
        XCTAssertEqual(audioID, "fr")
        XCTAssertEqual(subtitleID, "forced-fr")
    }

    func testSubtitleBackgroundStylesExposeStablePreferenceValues() {
        XCTAssertEqual(SubtitleBackgroundStyle.allCases, [.transparent, .subtle])
        XCTAssertEqual(SubtitleBackgroundStyle.transparent.rawValue, "transparent")
        XCTAssertEqual(SubtitleBackgroundStyle.subtle.rawValue, "subtle")
        XCTAssertEqual(
            SubtitleBackgroundStyle.defaultsKey,
            "reelfin.subtitle.background-style"
        )
        XCTAssertEqual(
            SubtitleBackgroundStyle.transparent.displayName,
            "Transparent Background"
        )
        XCTAssertEqual(
            SubtitleBackgroundStyle.subtle.displayName,
            "Subtle Background"
        )
    }

    func testSubtitleStylesHaveReferenceLabelsAndRealOpacityChanges() {
        XCTAssertEqual(SubtitleBackgroundStyle.transparent.displayName, "Transparent Background")
        XCTAssertEqual(SubtitleBackgroundStyle.subtle.displayName, "Subtle Background")
        XCTAssertEqual(
            CustomPlayerSubtitlePresentationPolicy.backgroundOpacity(
                for: .transparent,
                platform: .tvOS
            ),
            0
        )
        XCTAssertEqual(
            CustomPlayerSubtitlePresentationPolicy.backgroundOpacity(
                for: .subtle,
                platform: .tvOS
            ),
            0.45
        )
        XCTAssertEqual(
            CustomPlayerSubtitlePresentationPolicy.backgroundOpacity(
                for: .subtle,
                platform: .iOS
            ),
            0.30
        )
        XCTAssertEqual(
            SubtitleBackgroundStyle(rawValue: "unsupported") ?? .transparent,
            .transparent
        )
    }

    func testSubtitleOnRestoresLastTrackThenDefaultThenForcedThenFirst() {
        let first = PlaybackTrackOption(
            trackID: "first",
            title: "Spanish",
            badge: nil,
            iconName: nil,
            isSelected: false
        )
        let forced = PlaybackTrackOption(
            trackID: "forced",
            title: "French",
            badge: "Forced",
            iconName: nil,
            isSelected: false
        )
        let selected = PlaybackTrackOption(
            trackID: "selected",
            title: "English",
            badge: nil,
            iconName: nil,
            isSelected: true
        )

        XCTAssertEqual(
            NativePlayerSubtitleMenuPolicy.enabledTrackID(
                options: [first, forced, selected],
                lastEnabledID: "forced"
            ),
            "forced"
        )
        XCTAssertEqual(
            NativePlayerSubtitleMenuPolicy.enabledTrackID(
                options: [first, forced, selected],
                lastEnabledID: nil
            ),
            "selected"
        )
        XCTAssertEqual(
            NativePlayerSubtitleMenuPolicy.enabledTrackID(
                options: [first, forced],
                lastEnabledID: nil
            ),
            "forced"
        )
        XCTAssertEqual(
            NativePlayerSubtitleMenuPolicy.enabledTrackID(
                options: [first],
                lastEnabledID: nil
            ),
            "first"
        )
    }

    func testAVKitMenuFocusIsBoundedAndSubmenusReturnToRoot() {
        let rows: [NativePlayerAVKitMenuRowID] = [
            .subtitleOn,
            .subtitleOff,
            .subtitleLanguage,
            .subtitleStyle
        ]

        XCTAssertEqual(
            NativePlayerAVKitMenuFocusPolicy.move(from: .subtitleOn, delta: -1, rows: rows),
            .subtitleOn
        )
        XCTAssertEqual(
            NativePlayerAVKitMenuFocusPolicy.move(from: .subtitleOff, delta: 1, rows: rows),
            .subtitleLanguage
        )
        XCTAssertEqual(
            NativePlayerAVKitMenuFocusPolicy.parent(of: .subtitleLanguages),
            .subtitlesRoot
        )
    }

    func testAVKitMenuFocusHandlesEveryBoundaryWithoutOverflow() {
        let rows: [NativePlayerAVKitMenuRowID] = [
            .subtitleOn,
            .subtitleOff,
            .subtitleLanguage,
            .subtitleStyle
        ]

        XCTAssertEqual(
            NativePlayerAVKitMenuFocusPolicy.move(from: .subtitleStyle, delta: 1, rows: rows),
            .subtitleStyle
        )
        XCTAssertEqual(
            NativePlayerAVKitMenuFocusPolicy.move(
                from: .subtitleTrack("missing"),
                delta: 1,
                rows: rows
            ),
            .subtitleOn
        )
        XCTAssertEqual(
            NativePlayerAVKitMenuFocusPolicy.move(
                from: .subtitleTrack("missing"),
                delta: 1,
                rows: []
            ),
            .subtitleTrack("missing")
        )
        XCTAssertEqual(
            NativePlayerAVKitMenuFocusPolicy.move(
                from: .subtitleOff,
                delta: .max,
                rows: rows
            ),
            .subtitleStyle
        )
        XCTAssertEqual(
            NativePlayerAVKitMenuFocusPolicy.move(
                from: .subtitleLanguage,
                delta: .min,
                rows: rows
            ),
            .subtitleOn
        )
        XCTAssertEqual(
            NativePlayerAVKitMenuFocusPolicy.parent(of: .subtitleStyles),
            .subtitlesRoot
        )
    }

    func testTVChromeAvailableActionsRequireRealSelectableTracks() {
        let disabledOnly = PlaybackTrackOption(
            trackID: nil,
            title: "Désactivés",
            badge: nil,
            iconName: nil,
            isSelected: true
        )
        let subtitle = PlaybackTrackOption(
            trackID: "subtitle-1",
            title: "Français",
            badge: nil,
            iconName: nil,
            isSelected: false
        )
        let audioOne = PlaybackTrackOption(
            trackID: "audio-1",
            title: "Français",
            badge: nil,
            iconName: nil,
            isSelected: true
        )
        let audioTwo = PlaybackTrackOption(
            trackID: "audio-2",
            title: "English",
            badge: nil,
            iconName: nil,
            isSelected: false
        )

        XCTAssertEqual(
            NativePlayerTVChromeAvailability.actions(for: PlaybackControlsModel(
                audioOptions: [audioOne],
                subtitleOptions: [disabledOnly]
            )),
            [.video]
        )
        XCTAssertEqual(
            NativePlayerTVChromeAvailability.actions(for: PlaybackControlsModel(
                audioOptions: [audioOne, audioTwo],
                subtitleOptions: [disabledOnly, subtitle]
            )),
            [.subtitles, .audio, .video]
        )
        XCTAssertEqual(
            NativePlayerTVChromeAvailability.actions(for: PlaybackControlsModel(
                subtitleOptions: [subtitle]
            )),
            [.subtitles, .video]
        )
    }

    func testTVChromeCircularFocusMovesHorizontallyAndDownToTimeline() {
        let actions: [NativePlayerTVChromeAction] = [.subtitles, .audio, .video]

        XCTAssertEqual(
            NativePlayerTVChromeFocusGraph.destination(from: .subtitles, direction: .left, availableActions: actions),
            .subtitles
        )
        XCTAssertEqual(
            NativePlayerTVChromeFocusGraph.destination(from: .subtitles, direction: .right, availableActions: actions),
            .audio
        )
        XCTAssertEqual(
            NativePlayerTVChromeFocusGraph.destination(from: .audio, direction: .left, availableActions: actions),
            .subtitles
        )
        XCTAssertEqual(
            NativePlayerTVChromeFocusGraph.destination(from: .audio, direction: .right, availableActions: actions),
            .video
        )
        XCTAssertEqual(
            NativePlayerTVChromeFocusGraph.destination(from: .video, direction: .right, availableActions: actions),
            .video
        )
        for action in actions {
            XCTAssertEqual(
                NativePlayerTVChromeFocusGraph.destination(
                    from: .action(action),
                    direction: .down,
                    availableActions: actions
                ),
                .timeline
            )
        }
    }

    func testTVChromeTimelineFocusConnectsAvailableActionRowAndInfo() {
        XCTAssertEqual(
            NativePlayerTVChromeFocusGraph.destination(
                from: .timeline,
                direction: .up,
                availableActions: [.audio, .video]
            ),
            .audio
        )
        XCTAssertEqual(
            NativePlayerTVChromeFocusGraph.destination(
                from: .timeline,
                direction: .up,
                availableActions: [.video]
            ),
            .video
        )
        XCTAssertEqual(
            NativePlayerTVChromeFocusGraph.destination(
                from: .timeline,
                direction: .down,
                availableActions: [.video]
            ),
            .info
        )
    }

    func testTVChromeUtilityFocusMovesHorizontallyAndUpToTimeline() {
        XCTAssertEqual(
            NativePlayerTVChromeFocusGraph.destination(from: .info, direction: .left, availableActions: [.video]),
            .info
        )
        XCTAssertEqual(
            NativePlayerTVChromeFocusGraph.destination(from: .info, direction: .right, availableActions: [.video]),
            .insight
        )
        XCTAssertEqual(
            NativePlayerTVChromeFocusGraph.destination(from: .insight, direction: .left, availableActions: [.video]),
            .info
        )
        XCTAssertEqual(
            NativePlayerTVChromeFocusGraph.destination(from: .insight, direction: .right, availableActions: [.video]),
            .continueWatching
        )
        XCTAssertEqual(
            NativePlayerTVChromeFocusGraph.destination(
                from: .continueWatching,
                direction: .right,
                availableActions: [.video]
            ),
            .continueWatching
        )
        for action in NativePlayerTVChromeUtilityAction.allCases {
            XCTAssertEqual(
                NativePlayerTVChromeFocusGraph.destination(
                    from: .utility(action),
                    direction: .up,
                    availableActions: [.video]
                ),
                .timeline
            )
        }
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

    func testContinueWatchingSuppressesThePauseObserverRevealForOneTransition() {
        var transition = NativePlayerTVContinueWatchingTransition()

        transition.beginContinueWatching(isPaused: true)
        XCTAssertFalse(transition.shouldRevealChromeAfterPauseChange())
        XCTAssertTrue(transition.shouldRevealChromeAfterPauseChange())
    }

    func testLiveAutomationRequiresDebugTVOSOptInAndExactRedactedAlias() {
        let values = [
            "REELFIN_TV_UI_AUTOMATION": "1",
            "REELFIN_LIVE_UI_FIXTURE_ALIAS": "star-city-s1e1"
        ]
        XCTAssertTrue(TVLiveUIAutomationPolicy.isEnabled(isDebug: true, isTVOS: true, environment: values))
        XCTAssertFalse(TVLiveUIAutomationPolicy.isEnabled(isDebug: false, isTVOS: true, environment: values))
        XCTAssertFalse(TVLiveUIAutomationPolicy.isEnabled(isDebug: true, isTVOS: false, environment: values))
        XCTAssertFalse(TVLiveUIAutomationPolicy.isEnabled(
            isDebug: true,
            isTVOS: true,
            environment: [
                "REELFIN_TV_UI_AUTOMATION": "1",
                "REELFIN_LIVE_UI_FIXTURE_ALIAS": "not-the-fixture"
            ]
        ))
        XCTAssertEqual(TVLiveUIAutomationPolicy.minimumLoopCount(requested: 1), 10)
        XCTAssertEqual(TVLiveUIAutomationPolicy.minimumLoopCount(requested: 14), 14)
    }

    func testTVTrackPopoverUsesCompactRightSideMetrics() {
        let layout = NativePlayerTrackMenuLayout.tvOS

        XCTAssertEqual(layout.panelWidth, 460)
        XCTAssertEqual(layout.rowHeight, 58)
        XCTAssertEqual(layout.rowTitleSize, 22)
        XCTAssertEqual(layout.titleSize, 24)
        XCTAssertLessThanOrEqual(layout.contentMaxHeight, 360)
        XCTAssertLessThanOrEqual(layout.cornerRadius, 30)
    }

    func testTVTrackPopoverUsesTranslucentGlassAndDistinctSelectedFocusStates() {
        let style = NativePlayerTrackMenuVisualStyle.tvOS

        XCTAssertEqual(style.panelOpaqueFillOpacity, 0)
        XCTAssertLessThanOrEqual(style.panelBlackTintOpacity, 0.12)
        XCTAssertGreaterThanOrEqual(style.focusedFillOpacity, 0.22)
        XCTAssertLessThanOrEqual(style.focusedFillOpacity, 0.34)
        XCTAssertGreaterThan(style.selectedFillOpacity, 0)
        XCTAssertLessThan(style.selectedFillOpacity, style.focusedFillOpacity)
    }

    func testTVTrackPopoverStructuresRawJellyfinSubtitleLabels() {
        let forced = PlaybackTrackMenuOptionPresentation(
            option: PlaybackTrackOption(
                trackID: "forced",
                title: "VFF Forced - French - Default - SUBRIP",
                badge: nil,
                iconName: nil,
                isSelected: false
            )
        )
        XCTAssertEqual(forced.title, "Français · VFF")
        XCTAssertEqual(forced.details, "Forcé · Défaut · SRT")

        let sdh = PlaybackTrackMenuOptionPresentation(
            option: PlaybackTrackOption(
                trackID: "sdh",
                title: "VFF SDH - French - Hearing Impaired - SUBRIP",
                badge: nil,
                iconName: nil,
                isSelected: false
            )
        )
        XCTAssertEqual(sdh.title, "Français · VFF")
        XCTAssertEqual(sdh.details, "Malentendants · SRT")

        let english = PlaybackTrackMenuOptionPresentation(
            option: PlaybackTrackOption(
                trackID: "english",
                title: "English - SUBRIP",
                badge: nil,
                iconName: nil,
                isSelected: true
            )
        )
        XCTAssertEqual(english.title, "Anglais")
        XCTAssertEqual(english.details, "SRT")
    }

    func testTrackAccessibilityLabelDistinguishesSameLanguageAudioOptions() {
        let dolby = PlaybackTrackOption(
            trackID: "dolby",
            title: "English",
            badge: "Dolby Digital+ · Default",
            iconName: nil,
            isSelected: true
        )
        let aac = PlaybackTrackOption(
            trackID: "aac",
            title: "English",
            badge: "AAC",
            iconName: nil,
            isSelected: false
        )

        XCTAssertNotEqual(dolby.accessibilityLabel, aac.accessibilityLabel)
        XCTAssertEqual(dolby.accessibilityLabel, "English, Dolby Digital+ · Default")
    }

    func testCustomAudioOptionsDisambiguateDuplicateDisplayNames() {
        let options = PlaybackControlsModel.customAudioOptions(from: [
            CustomPlaybackAudioTrack(id: "audio-0", title: "English", isSelected: true),
            CustomPlaybackAudioTrack(id: "audio-1", title: "English", isSelected: false)
        ])

        XCTAssertEqual(options.map(\.badge), ["Piste 1", "Piste 2"])
        XCTAssertEqual(options.map(\.accessibilityLabel), ["English, Piste 1", "English, Piste 2"])
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
