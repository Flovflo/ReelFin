import AVFoundation
import CoreGraphics
@testable import PlaybackEngine
@testable import ReelFinUI
import Shared
import XCTest

@MainActor
final class PlaybackSessionControllerTrackReloadTests: XCTestCase {
    func testPlaybackControlsModelExposesSelectableAudioAndSubtitleTracks() {
        let audioTracks = [
            MediaTrack(id: "audio-en", title: "English AAC", language: "eng", codec: "aac", isDefault: true, index: 1),
            MediaTrack(id: "audio-fr", title: "French E-AC-3", language: "fra", codec: "eac3", isDefault: false, index: 2)
        ]
        let subtitleTracks = [
            MediaTrack(id: "sub-fr", title: "French", language: "fra", codec: "srt", isDefault: true, index: 3),
            MediaTrack(id: "sub-en", title: "English forced", language: "eng", codec: "srt", isDefault: false, isForced: true, index: 4)
        ]

        let model = PlaybackControlsModel.make(
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            selectedAudioID: "audio-fr",
            selectedSubtitleID: nil,
            skipSuggestion: nil
        )

        XCTAssertTrue(model.hasSelectableTracks)
        XCTAssertEqual(model.audioOptions.map(\.trackID), ["audio-en", "audio-fr"])
        XCTAssertEqual(model.options(for: .audio).map(\.trackID), ["audio-en", "audio-fr"])
        XCTAssertTrue(model.audioOptions.first { $0.trackID == "audio-fr" }?.isSelected == true)
        XCTAssertEqual(model.subtitleOptions.map(\.trackID), [nil, "sub-fr", "sub-en"])
        XCTAssertEqual(model.options(for: .subtitles).map(\.trackID), [nil, "sub-fr", "sub-en"])
        XCTAssertEqual(model.subtitleOptions.first?.title, "Off")
        XCTAssertTrue(model.subtitleOptions.first?.isSelected == true)
    }

    func testPlaybackControlsModelHidesSingleAudioTrackButKeepsSubtitleToggle() {
        let model = PlaybackControlsModel.make(
            audioTracks: [
                MediaTrack(id: "audio-fr", title: "French AAC", language: "fra", codec: "aac", isDefault: true, index: 1)
            ],
            subtitleTracks: [
                MediaTrack(id: "sub-fr", title: "French", language: "fra", codec: "srt", isDefault: false, index: 2)
            ],
            selectedAudioID: "audio-fr",
            selectedSubtitleID: "sub-fr",
            skipSuggestion: nil
        )

        XCTAssertTrue(model.hasSelectableTracks)
        XCTAssertTrue(model.audioOptions.isEmpty)
        XCTAssertEqual(model.subtitleOptions.count, 2)
        XCTAssertTrue(model.subtitleOptions.first { $0.trackID == "sub-fr" }?.isSelected == true)
    }

    func testStartupSubtitleLoadActionAppliesEmbeddedTrack() {
        let action = PlaybackSessionController.startupSubtitleLoadAction(
            autoSelectedTrackID: "sub-fr",
            isEmbedded: true
        )

        XCTAssertEqual(action, .applyEmbedded("sub-fr"))
    }

    func testStartupSubtitleLoadActionSkipsExternalTrack() {
        let action = PlaybackSessionController.startupSubtitleLoadAction(
            autoSelectedTrackID: "sub-fr-forced",
            isEmbedded: false
        )

        XCTAssertEqual(action, .skipExternal("sub-fr-forced"))
    }

    func testStartupSubtitleLoadActionIgnoresMissingTrack() {
        let action = PlaybackSessionController.startupSubtitleLoadAction(
            autoSelectedTrackID: nil,
            isEmbedded: false
        )

        XCTAssertEqual(action, .none)
    }

    func testTvOSHDRDirectPlaySkipsVideoOutputProbe() {
        let source = MediaSource(
            id: "dolby-vision-source",
            itemID: "item-dv",
            name: "Dolby Vision stream",
            container: "mp4",
            videoCodec: "dvh1",
            audioCodec: "eac3",
            bitrate: 21_000_000,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldAttachVideoOutputProbe(
                route: .directPlay(URL(string: "https://example.com/Videos/item-dv/stream?static=true")!),
                source: source,
                isTVOS: true
            )
        )
    }

    func testIOSHDRDirectPlayKeepsVideoOutputProbe() {
        let source = MediaSource(
            id: "dolby-vision-source",
            itemID: "item-dv",
            name: "Dolby Vision stream",
            container: "mp4",
            videoCodec: "dvh1",
            audioCodec: "eac3",
            bitrate: 21_000_000,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        XCTAssertTrue(
            PlaybackSessionController.shouldAttachVideoOutputProbe(
                route: .directPlay(URL(string: "https://example.com/Videos/item-dv/stream?static=true")!),
                source: source,
                isTVOS: false
            )
        )
    }

    func testTvOSSDRDirectPlayKeepsVideoOutputProbe() {
        let source = MediaSource(
            id: "sdr-source",
            itemID: "item-sdr",
            name: "SDR stream",
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            bitrate: 5_000_000,
            videoBitDepth: 8,
            videoRangeType: "SDR",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        XCTAssertTrue(
            PlaybackSessionController.shouldAttachVideoOutputProbe(
                route: .directPlay(URL(string: "https://example.com/Videos/item-sdr/stream?static=true")!),
                source: source,
                isTVOS: true
            )
        )
    }

    func testTvOSHDRDirectPlayDoesNotAutoSelectDefaultNonForcedSubtitle() {
        let source = MediaSource(
            id: "dolby-vision-source",
            itemID: "item-dv",
            name: "Dolby Vision stream",
            container: "mp4",
            videoCodec: "dvh1",
            audioCodec: "eac3",
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
        let track = MediaTrack(
            id: "sub-fr-default",
            title: "French - Default - MOV_TEXT",
            language: "fra",
            codec: "mov_text",
            isDefault: true,
            isForced: false,
            index: 3
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldAutoSelectDefaultSubtitleAtStartup(
                track: track,
                route: .directPlay(URL(string: "https://example.com/Videos/item-dv/stream?static=true")!),
                source: source,
                isTVOS: true
            )
        )
    }

    func testTvOSHDRDirectPlayStillAutoSelectsForcedSubtitle() {
        let source = MediaSource(
            id: "dolby-vision-source",
            itemID: "item-dv",
            name: "Dolby Vision stream",
            container: "mp4",
            videoCodec: "dvh1",
            audioCodec: "eac3",
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
        let track = MediaTrack(
            id: "sub-fr-forced",
            title: "French Forced - MOV_TEXT",
            language: "fra",
            codec: "mov_text",
            isDefault: true,
            isForced: true,
            index: 3
        )

        XCTAssertTrue(
            PlaybackSessionController.shouldAutoSelectDefaultSubtitleAtStartup(
                track: track,
                route: .directPlay(URL(string: "https://example.com/Videos/item-dv/stream?static=true")!),
                source: source,
                isTVOS: true
            )
        )
    }

    func testVideoFormatSnapshotDetectsDolbyVisionFromCodec() {
        let snapshot = PlaybackSessionController.videoFormatSnapshot(
            codecFourCC: "dvh1",
            extensions: [:],
            fallbackBitDepth: 10
        )

        XCTAssertEqual(snapshot.codecFourCC, "dvh1")
        XCTAssertEqual(snapshot.bitDepth, 10)
        XCTAssertEqual(snapshot.hdrMode, .dolbyVision)
        XCTAssertEqual(snapshot.hdrTransfer, "PQ")
        XCTAssertTrue(snapshot.dolbyVisionActive)
    }

    func testVideoFormatSnapshotDetectsHDR10FromColorMetadata() {
        let snapshot = PlaybackSessionController.videoFormatSnapshot(
            codecFourCC: "hvc1",
            extensions: [
                kCMFormatDescriptionExtension_TransferFunction: kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String,
                kCMFormatDescriptionExtension_ColorPrimaries: kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String,
                kCMFormatDescriptionExtension_Depth: NSNumber(value: 10)
            ],
            fallbackBitDepth: nil
        )

        XCTAssertEqual(snapshot.codecFourCC, "hvc1")
        XCTAssertEqual(snapshot.bitDepth, 10)
        XCTAssertEqual(snapshot.hdrMode, .hdr10)
        XCTAssertEqual(snapshot.hdrTransfer, "PQ")
        XCTAssertFalse(snapshot.dolbyVisionActive)
    }

    func testTrackReloadResumeDecisionPreservesExplicitPlayingState() {
        let shouldResume = PlaybackSessionController.shouldResumePlaybackAfterTrackReload(
            wasPlayingBeforeReplacement: true,
            playerRate: 0,
            timeControlStatus: .paused
        )

        XCTAssertTrue(shouldResume)
    }

    func testTrackReloadResumeDecisionUsesUnderlyingPlayerSignals() {
        XCTAssertTrue(
            PlaybackSessionController.shouldResumePlaybackAfterTrackReload(
                wasPlayingBeforeReplacement: false,
                playerRate: 1,
                timeControlStatus: .paused
            )
        )

        XCTAssertTrue(
            PlaybackSessionController.shouldResumePlaybackAfterTrackReload(
                wasPlayingBeforeReplacement: false,
                playerRate: 0,
                timeControlStatus: .playing
            )
        )
    }

    func testTrackReloadResumeDecisionKeepsPausedSessionsPaused() {
        let shouldResume = PlaybackSessionController.shouldResumePlaybackAfterTrackReload(
            wasPlayingBeforeReplacement: false,
            playerRate: 0,
            timeControlStatus: .paused
        )

        XCTAssertFalse(shouldResume)
    }

    func testControllerReattachResumeDecisionTreatsWaitingStateAsPlaybackIntent() {
        let shouldResume = PlaybackResumePolicy.shouldResumeAfterControllerReattach(
            playerRate: 0,
            timeControlStatus: .waitingToPlayAtSpecifiedRate
        )

        XCTAssertTrue(shouldResume)
    }

    func testControllerReattachResumeDecisionKeepsExplicitPausePaused() {
        let shouldResume = PlaybackResumePolicy.shouldResumeAfterControllerReattach(
            playerRate: 0,
            timeControlStatus: .paused
        )

        XCTAssertFalse(shouldResume)
    }

    func testControllerReattachPausesAudioDuringDetachWhenPlaybackIsActive() {
        let intent = PlaybackResumePolicy.controllerReattachPlaybackIntent(
            playerRate: 1,
            timeControlStatus: .playing
        )

        XCTAssertTrue(intent.pauseDuringDetach)
        XCTAssertTrue(intent.resumeAfterAttach)
    }

    func testControllerReattachDoesNotPauseExplicitlyPausedPlayback() {
        let intent = PlaybackResumePolicy.controllerReattachPlaybackIntent(
            playerRate: 0,
            timeControlStatus: .paused
        )

        XCTAssertFalse(intent.pauseDuringDetach)
        XCTAssertFalse(intent.resumeAfterAttach)
    }

    func testResumeSecondsPrefersServerPositionWhenLocalProgressIsEarlier() {
        let item = MediaItem(
            id: "movie-1",
            name: "Movie",
            mediaType: .movie,
            runtimeTicks: Int64(90 * 60 * 10_000_000),
            playbackPositionTicks: Int64(10 * 60 * 10_000_000)
        )
        let localProgress = PlaybackProgress(
            itemID: "movie-1",
            positionTicks: Int64(11.4 * 10_000_000),
            totalTicks: Int64(90 * 60 * 10_000_000),
            updatedAt: Date()
        )

        let seconds = PlaybackSessionController.resolvedResumeSeconds(
            for: item,
            localProgress: localProgress
        )

        XCTAssertEqual(seconds ?? -1, 600, accuracy: 0.001)
    }

    func testResumeSecondsKeepsLaterLocalProgressWhenServerIsBehind() {
        let item = MediaItem(
            id: "movie-1",
            name: "Movie",
            mediaType: .movie,
            runtimeTicks: Int64(90 * 60 * 10_000_000),
            playbackPositionTicks: Int64(8 * 60 * 10_000_000)
        )
        let localProgress = PlaybackProgress(
            itemID: "movie-1",
            positionTicks: Int64(12 * 60 * 10_000_000),
            totalTicks: Int64(90 * 60 * 10_000_000),
            updatedAt: Date()
        )

        let seconds = PlaybackSessionController.resolvedResumeSeconds(
            for: item,
            localProgress: localProgress
        )

        XCTAssertEqual(seconds ?? -1, 720, accuracy: 0.001)
    }

    func testControllerUpdateDefersAssignmentDuringTemporaryReattachDetach() {
        XCTAssertTrue(
            NativePlayerViewController.Coordinator.shouldDeferPlayerAssignmentDuringReattach(
                isTemporarilyDetachedForReattach: true,
                controllerPlayerIsNil: true,
                observedPlayerMatches: true
            )
        )

        XCTAssertFalse(
            NativePlayerViewController.Coordinator.shouldDeferPlayerAssignmentDuringReattach(
                isTemporarilyDetachedForReattach: true,
                controllerPlayerIsNil: false,
                observedPlayerMatches: true
            )
        )

        XCTAssertFalse(
            NativePlayerViewController.Coordinator.shouldDeferPlayerAssignmentDuringReattach(
                isTemporarilyDetachedForReattach: true,
                controllerPlayerIsNil: true,
                observedPlayerMatches: false
            )
        )
    }

    func testPremiumProgressiveDirectPlayUsesFastStartupBufferingOniOS() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 14_885_349,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let policy = PlaybackSessionController.directPlayStabilityPolicy(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            defaultForwardBufferDuration: 2,
            defaultWaitsToMinimizeStalling: false,
            isTVOS: false
        )

        XCTAssertEqual(policy.forwardBufferDuration, 2)
        XCTAssertFalse(policy.waitsToMinimizeStalling)
        XCTAssertNil(policy.reason)
    }

    func testHighBitrateProgressiveDirectPlayUsesNoStallBufferingOniOS() {
        let source = MediaSource(
            id: "high-bitrate-source",
            itemID: "item-high-bitrate",
            name: "High bitrate stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "aac",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "HDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let policy = PlaybackSessionController.directPlayStabilityPolicy(
            route: .directPlay(URL(string: "https://example.com/Videos/item-high-bitrate/stream?static=true&MediaSourceId=high-bitrate-source")!),
            source: source,
            defaultForwardBufferDuration: 2,
            defaultWaitsToMinimizeStalling: false,
            isTVOS: false
        )

        XCTAssertEqual(policy.forwardBufferDuration, 12)
        XCTAssertTrue(policy.waitsToMinimizeStalling)
        XCTAssertEqual(policy.reason, "ios_no_stall_directplay_guard")
    }

    func testHighBitrateProgressiveDirectPlayUsesNoStallBufferingOnTvOS() {
        let source = MediaSource(
            id: "high-bitrate-source",
            itemID: "item-high-bitrate",
            name: "High bitrate stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "aac",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "HDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let policy = PlaybackSessionController.directPlayStabilityPolicy(
            route: .directPlay(URL(string: "https://example.com/Videos/item-high-bitrate/stream?static=true&MediaSourceId=high-bitrate-source")!),
            source: source,
            defaultForwardBufferDuration: 2,
            defaultWaitsToMinimizeStalling: false,
            isTVOS: true
        )

        XCTAssertEqual(policy.forwardBufferDuration, 24)
        XCTAssertTrue(policy.waitsToMinimizeStalling)
        XCTAssertEqual(policy.reason, "tvos_no_stall_directplay_guard")
    }

    func testPresentationSizeAloneDoesNotCountAsRenderedFrameWhenOutputIsAttached() {
        XCTAssertFalse(
            PlaybackSessionController.hasRenderableVideoFrame(
                copiedPixelBuffer: false,
                presentationSize: CGSize(width: 3840, height: 1608),
                videoOutputAttached: true,
                avkitReadyForDisplay: false,
                requiresDisplayReadyWhenVideoOutputDetached: false
            )
        )
    }

    func testCopiedPixelBufferCountsAsRenderedFrame() {
        XCTAssertTrue(
            PlaybackSessionController.hasRenderableVideoFrame(
                copiedPixelBuffer: true,
                presentationSize: CGSize(width: 3840, height: 1608),
                videoOutputAttached: true,
                avkitReadyForDisplay: false,
                requiresDisplayReadyWhenVideoOutputDetached: false
            )
        )
    }

    func testTvOSHDRDirectPlayCannotUsePresentationSizeAsRenderedFrameProof() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium HDR stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "HDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
        let route = PlaybackRoute.directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!)

        XCTAssertTrue(PlaybackSessionController.requiresAVKitReadyForDisplayProof(
            route: route,
            source: source,
            isTVOS: true
        ))
        XCTAssertFalse(
            PlaybackSessionController.hasRenderableVideoFrame(
                copiedPixelBuffer: false,
                presentationSize: CGSize(width: 3840, height: 1608),
                videoOutputAttached: false,
                avkitReadyForDisplay: false,
                requiresDisplayReadyWhenVideoOutputDetached: true
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.hasRenderableVideoFrame(
                copiedPixelBuffer: false,
                presentationSize: CGSize(width: 3840, height: 1608),
                videoOutputAttached: false,
                avkitReadyForDisplay: true,
                requiresDisplayReadyWhenVideoOutputDetached: true
            )
        )
    }

    func testAVKitReadyForDisplayIsAcceptedOnlyAfterPlayerItemReady() {
        XCTAssertFalse(PlaybackSessionController.shouldAcceptAVKitReadyForDisplay(itemStatus: .unknown))
        XCTAssertTrue(PlaybackSessionController.shouldAcceptAVKitReadyForDisplay(itemStatus: .readyToPlay))
        XCTAssertFalse(PlaybackSessionController.shouldAcceptAVKitReadyForDisplay(itemStatus: .failed))
    }

    func testHighBitrateIPhoneDirectPlayPrerollsVideoBeforeAudioStart() {
        let source = MediaSource(
            id: "high-bitrate-source",
            itemID: "item-high-bitrate",
            name: "High bitrate stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "aac",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "HDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        XCTAssertTrue(
            PlaybackSessionController.shouldPrerollVideoBeforeAudioStart(
                route: .directPlay(URL(string: "https://example.com/Videos/item-high-bitrate/stream?static=true")!),
                source: source,
                isTVOS: false
            )
        )
    }

    func testTvOSPremiumDirectPlaySkipsBlockingVideoPreroll() {
        let source = MediaSource(
            id: "high-bitrate-source",
            itemID: "item-high-bitrate",
            name: "High bitrate stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "aac",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "HDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldPrerollVideoBeforeAudioStart(
                route: .directPlay(URL(string: "https://example.com/Videos/item-high-bitrate/stream?static=true")!),
                source: source,
                isTVOS: true
            )
        )
    }

    func testTvOSOrdinaryDirectPlaySkipsVideoPrerollGate() {
        let source = MediaSource(
            id: "ordinary-source",
            itemID: "item-ordinary",
            name: "Ordinary stream",
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            bitrate: 6_000_000,
            videoBitDepth: 8,
            videoRangeType: "SDR",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldPrerollVideoBeforeAudioStart(
                route: .directPlay(URL(string: "https://example.com/Videos/item-ordinary/stream?static=true")!),
                source: source,
                isTVOS: true
            )
        )
    }

    func testPremiumProgressiveDirectPlayUsesNoStallBufferingOnTvOS() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 14_885_349,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let policy = PlaybackSessionController.directPlayStabilityPolicy(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            defaultForwardBufferDuration: 2,
            defaultWaitsToMinimizeStalling: false,
            isTVOS: true
        )

        XCTAssertEqual(policy.forwardBufferDuration, 24)
        XCTAssertTrue(policy.waitsToMinimizeStalling)
        XCTAssertEqual(policy.reason, "tvos_no_stall_directplay_guard")
    }

    func testPremiumDirectPlayPrefersProvidedStableURLAndPreservesQueryItems() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 14_885_349,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/Videos/item-premium/stream?MediaSourceId=premium-source")!,
            directPlayURL: URL(string: "https://example.com/Videos/item-premium/direct.mp4")!
        )
        let currentURL = URL(
            string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source&AudioStreamIndex=2&api_key=token-1"
        )!

        let preferredURL = PlaybackSessionController.preferredDirectPlayAssetURL(
            route: .directPlay(currentURL),
            source: source,
            currentAssetURL: currentURL
        )

        let components = URLComponents(url: preferredURL, resolvingAgainstBaseURL: false)
        let queryMap: [String: String] = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name.lowercased(), value)
        })

        XCTAssertEqual(preferredURL.path, "/Videos/item-premium/direct.mp4")
        XCTAssertEqual(queryMap["audiostreamindex"], "2")
        XCTAssertEqual(queryMap["api_key"], "token-1")
        XCTAssertEqual(queryMap["mediasourceid"], "premium-source")
        XCTAssertNil(queryMap["static"])
    }

    func testPremiumDirectPlayBuildsStaticStreamExtensionAliasWhenServerURLHasNoExtension() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            videoCodec: "hvc1",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
        let currentURL = URL(
            string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source&api_key=token-1"
        )!

        let preferredURL = PlaybackSessionController.preferredDirectPlayAssetURL(
            route: .directPlay(currentURL),
            source: source,
            currentAssetURL: currentURL
        )

        XCTAssertEqual(preferredURL.path, "/Videos/item-premium/stream.mp4")
        let queryItems = URLComponents(url: preferredURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(queryItems.first { $0.name.caseInsensitiveCompare("api_key") == .orderedSame }?.value, "token-1")
        XCTAssertEqual(queryItems.first { $0.name.caseInsensitiveCompare("MediaSourceId") == .orderedSame }?.value, "premium-source")
    }

    func testPremiumDirectPlayExtensionAliasPrefersRealFileExtension() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            filePath: "/media/Premium Movie.mov",
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            videoCodec: "hvc1",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
        let currentURL = URL(
            string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source&api_key=token-1"
        )!

        let aliasURL = PlaybackSessionController.extensionAliasURL(for: currentURL, source: source)

        XCTAssertEqual(aliasURL?.path, "/Videos/item-premium/stream.mov")
    }

    func testPremiumDirectPlayKeepsCurrentURLWhenNoBetterServerURLExists() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 14_885_349,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
        let currentURL = URL(
            string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source&AudioStreamIndex=2&api_key=token-1"
        )!

        let preferredURL = PlaybackSessionController.preferredDirectPlayAssetURL(
            route: .directPlay(currentURL),
            source: source,
            currentAssetURL: currentURL
        )

        XCTAssertEqual(preferredURL, currentURL)
    }

    func testStandardDirectPlayKeepsOriginalBufferPolicy() {
        let source = MediaSource(
            id: "standard-source",
            itemID: "item-standard",
            name: "Standard stream",
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            bitrate: 4_000_000,
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let policy = PlaybackSessionController.directPlayStabilityPolicy(
            route: .directPlay(URL(string: "https://example.com/Videos/item-standard/stream?static=true&MediaSourceId=standard-source")!),
            source: source,
            defaultForwardBufferDuration: 2,
            defaultWaitsToMinimizeStalling: false,
            isTVOS: false
        )

        XCTAssertEqual(policy.forwardBufferDuration, 2)
        XCTAssertFalse(policy.waitsToMinimizeStalling)
        XCTAssertNil(policy.reason)
    }

    func testStandardDirectPlayKeepsCurrentURL() {
        let source = MediaSource(
            id: "standard-source",
            itemID: "item-standard",
            name: "Standard stream",
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            bitrate: 4_000_000,
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directPlayURL: URL(string: "https://example.com/Videos/item-standard/direct.mp4")!
        )
        let currentURL = URL(
            string: "https://example.com/Videos/item-standard/stream?static=true&MediaSourceId=standard-source&api_key=token-1"
        )!

        let preferredURL = PlaybackSessionController.preferredDirectPlayAssetURL(
            route: .directPlay(currentURL),
            source: source,
            currentAssetURL: currentURL
        )

        XCTAssertEqual(preferredURL, currentURL)
    }

    func testRepeatedPremiumDirectPlayStallsBeforeFirstFrameTriggerRecovery() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 14_885_349,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let shouldRecover = PlaybackSessionController.shouldAttemptDirectPlayStallRecovery(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            recentStallCount: 2,
            elapsedSecondsSinceLoad: 6,
            elapsedSecondsSinceFirstFrame: nil
        )

        XCTAssertTrue(shouldRecover)
    }

    func testEarlyPostFirstFrameDirectPlayStallsTriggerRecovery() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 14_885_349,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let shouldRecover = PlaybackSessionController.shouldAttemptDirectPlayStallRecovery(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            recentStallCount: 2,
            elapsedSecondsSinceLoad: 15,
            elapsedSecondsSinceFirstFrame: 2
        )

        XCTAssertTrue(shouldRecover)
    }

    func testSingleDirectPlayStallBeforeFirstFrameDoesNotTriggerRecovery() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 14_885_349,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let shouldRecover = PlaybackSessionController.shouldAttemptDirectPlayStallRecovery(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            recentStallCount: 1,
            elapsedSecondsSinceLoad: 6,
            elapsedSecondsSinceFirstFrame: nil
        )

        XCTAssertFalse(shouldRecover)
    }

    func testSingleDirectPlayStallRightAfterFirstFrameTriggersRecovery() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 14_885_349,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let shouldRecover = PlaybackSessionController.shouldAttemptDirectPlayStallRecovery(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            recentStallCount: 1,
            elapsedSecondsSinceLoad: 18,
            elapsedSecondsSinceFirstFrame: 10
        )

        XCTAssertTrue(shouldRecover)
    }

    func testPostStartDirectPlayStallPreservesDirectRouteRecovery() {
        XCTAssertFalse(
            PlaybackSessionController.shouldDisableDirectRoutesForRecovery(
                reason: StartupFailureReason.directPlayPostStartStall.rawValue
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldSuspendCurrentItemBeforeProfileRecovery(
                reason: StartupFailureReason.directPlayPostStartStall.rawValue
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldAttemptSameRouteDirectPlayRecovery(
                reason: StartupFailureReason.directPlayPostStartStall.rawValue
            )
        )
        XCTAssertFalse(StartupFailureReason.directPlayPostStartStall.shouldTriggerRecovery)
    }

    func testDirectPlayVideoDecodeFailuresUseSameRouteRecovery() {
        for reason in [
            StartupFailureReason.audioOnlyNoVideo,
            .decodedFrameWatchdog,
            .readyButNoVideoFrame,
            .presentationSizeZero,
            .playerItemFailed
        ] {
            XCTAssertTrue(
                PlaybackSessionController.shouldAttemptSameRouteDirectPlayRecovery(
                    reason: reason.rawValue
                ),
                reason.rawValue
            )
            XCTAssertTrue(
                PlaybackSessionController.shouldSuspendCurrentItemBeforeProfileRecovery(
                    reason: reason.rawValue
                ),
                reason.rawValue
            )
            XCTAssertTrue(reason.shouldTriggerRecovery, reason.rawValue)
        }
    }

    func testTvOSHighBitrateDirectPlayBlocksAutoplayOnSparseBufferTelemetry() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "aac",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "HDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let shouldBlock = PlaybackSessionController.shouldBlockAutoplayAfterUnsafeStartup(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            runtimeSeconds: 7_200,
            resumeSeconds: 1_102,
            isTVOS: true
        )

        XCTAssertTrue(shouldBlock)
    }

    func testTvOSHighBitrateWithinBudgetDirectPlayKeepsNativePath() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mov",
            videoCodec: "hevc",
            audioCodec: "aac",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "HDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let shouldPreempt = PlaybackSessionController.shouldPreemptivelyUseStableTVOSHLS(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            playbackPolicy: .auto,
            allowSDRFallback: true,
            usesDirectRemuxOnly: false,
            maxStreamingBitrate: 120_000_000,
            isTVOS: true
        )

        XCTAssertFalse(shouldPreempt)
    }

    func testTvOSHighBitrateOverBudgetDirectPlayStillKeepsNativePath() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mov",
            videoCodec: "hevc",
            audioCodec: "aac",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "HDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let shouldPreempt = PlaybackSessionController.shouldPreemptivelyUseStableTVOSHLS(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            playbackPolicy: .auto,
            allowSDRFallback: true,
            usesDirectRemuxOnly: false,
            maxStreamingBitrate: 12_000_000,
            isTVOS: true
        )

        XCTAssertFalse(shouldPreempt)
    }

    func testTvOSHighBitrateStrictQualityDirectPlayKeepsNativePath() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mov",
            videoCodec: "hevc",
            audioCodec: "aac",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "HDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let shouldPreempt = PlaybackSessionController.shouldPreemptivelyUseStableTVOSHLS(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            playbackPolicy: .auto,
            allowSDRFallback: false,
            usesDirectRemuxOnly: false,
            maxStreamingBitrate: 40_000_000,
            isTVOS: true
        )

        XCTAssertFalse(shouldPreempt)
    }

    func testTvOSHighBitrateDirectPlayWithNetworkHeadroomUsesFastStartupPolicy() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mov",
            videoCodec: "hevc",
            audioCodec: "aac",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "HDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let policy = PlaybackSessionController.directPlayStabilityPolicy(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            defaultForwardBufferDuration: 2,
            defaultWaitsToMinimizeStalling: false,
            maxStreamingBitrate: 120_000_000,
            isTVOS: true
        )

        XCTAssertEqual(policy.forwardBufferDuration, 2)
        XCTAssertFalse(policy.waitsToMinimizeStalling)
        XCTAssertNil(policy.reason)
    }

    func testStartupDirectPlayFailuresUseSameRouteForRenderFailuresAndStalls() {
        XCTAssertFalse(
            PlaybackSessionController.shouldAttemptSameRouteDirectPlayRecovery(
                reason: StartupFailureReason.startupReadinessTimeout.rawValue
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldAttemptSameRouteDirectPlayRecovery(
                reason: StartupFailureReason.directPlayPreflightInsufficient.rawValue
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldAttemptSameRouteDirectPlayRecovery(
                reason: StartupFailureReason.audioOnlyNoVideo.rawValue
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldAttemptSameRouteDirectPlayRecovery(
                reason: StartupFailureReason.playerItemFailed.rawValue
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldAttemptSameRouteDirectPlayRecovery(
                reason: StartupFailureReason.readyButNoVideoFrame.rawValue
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldAttemptSameRouteDirectPlayRecovery(
                reason: StartupFailureReason.directPlayStall.rawValue
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldAttemptSameRouteDirectPlayRecovery(
                reason: StartupFailureReason.directPlayPostStartStall.rawValue
            )
        )
    }

    func testTvOSHighBitrateDirectPlayPrestartGuardRejectsLowHeadroomPreheat() {
        let preheat = PlaybackStartupPreheater.Result(
            byteCount: 4 * 1_024 * 1_024,
            elapsedSeconds: 2.368,
            observedBitrate: 14_170_226,
            rangeStart: 6_333_399_040,
            reason: "directplay_range"
        )

        let reason = PlaybackSessionController.directPlayPrestartRecoveryReason(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            sourceBitrate: 21_868_794,
            preheatResult: preheat,
            isTVOS: true
        )

        XCTAssertEqual(reason, .directPlayPreflightInsufficient)
    }

    func testTvOSHighBitrateDirectPlayPrestartGuardAcceptsHealthyHeadroom() {
        let preheat = PlaybackStartupPreheater.Result(
            byteCount: 4 * 1_024 * 1_024,
            elapsedSeconds: 0.8,
            observedBitrate: 48_000_000,
            rangeStart: 6_333_399_040,
            reason: "directplay_range"
        )

        let reason = PlaybackSessionController.directPlayPrestartRecoveryReason(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            sourceBitrate: 21_868_794,
            preheatResult: preheat,
            isTVOS: true
        )

        XCTAssertNil(reason)
    }

    func testTvOSHighBitrateDirectPlayPrestartGuardRejectsMissingPreheat() {
        let reason = PlaybackSessionController.directPlayPrestartRecoveryReason(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            sourceBitrate: 21_868_794,
            preheatResult: nil,
            isTVOS: true
        )

        XCTAssertEqual(reason, .directPlayPreflightInsufficient)
    }

    func testDirectPlayResumePositionToleranceAcceptsLandedSeek() {
        XCTAssertTrue(
            PlaybackSessionController.isResumePositionSatisfied(
                currentTime: 2_325.49,
                resumeSeconds: 2_325.5
            )
        )
    }

    func testDirectPlayResumePositionToleranceRejectsWrongStart() {
        XCTAssertFalse(
            PlaybackSessionController.isResumePositionSatisfied(
                currentTime: 0.16,
                resumeSeconds: 2_325.5
            )
        )
    }

    func testResumeOffsetDoesNotTripDecodedFrameWatchdogBeforeHLSTimeAdvances() {
        XCTAssertFalse(
            PlaybackSessionController.decodedFrameWatchdogPlaybackHasStarted(
                playerSeconds: 0.08,
                absolutePlaybackSeconds: 1_119.08,
                transcodeStartOffset: 1_119
            )
        )
    }

    func testHLSTimeAdvanceTripsDecodedFrameWatchdogAfterResumeOffset() {
        XCTAssertTrue(
            PlaybackSessionController.decodedFrameWatchdogPlaybackHasStarted(
                playerSeconds: 1.0,
                absolutePlaybackSeconds: 1_120,
                transcodeStartOffset: 1_119
            )
        )
    }

    func testPremiumDirectPlayGetsExtendedStartupWatchdogs() {
        XCTAssertEqual(
            PlaybackSessionController.decodedFrameWatchdogDelayNanoseconds(
                activeProfile: .serverDefault,
                isHEVCStreamCopyTranscode: false,
                isStallResistantDirectPlay: true
            ),
            30_000_000_000
        )
        XCTAssertEqual(
            PlaybackSessionController.startupWatchdogDelayNanoseconds(
                activeProfile: .serverDefault,
                currentItemHasDolbyVision: false,
                isHEVCStreamCopyTranscode: false,
                isStallResistantDirectPlay: true
            ),
            30_000_000_000
        )
    }

    func testPermissiveLowBitrateTvOSDirectPlayDoesNotBlockAutoplayAfterTimeout() {
        let source = MediaSource(
            id: "ordinary-source",
            itemID: "item-ordinary",
            name: "Ordinary stream",
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            bitrate: 3_500_000,
            videoBitDepth: 8,
            videoRangeType: "SDR",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let shouldBlock = PlaybackSessionController.shouldBlockAutoplayAfterUnsafeStartup(
            route: .directPlay(URL(string: "https://example.com/Videos/item-ordinary/stream?static=true&MediaSourceId=ordinary-source")!),
            source: source,
            runtimeSeconds: 7_200,
            resumeSeconds: 0,
            isTVOS: true
        )

        XCTAssertFalse(shouldBlock)
    }

    func testLatePlaybackStallsDoNotTriggerStartupRecovery() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 14_885_349,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let shouldRecover = PlaybackSessionController.shouldAttemptDirectPlayStallRecovery(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            recentStallCount: 2,
            elapsedSecondsSinceLoad: 30,
            elapsedSecondsSinceFirstFrame: 24
        )

        XCTAssertFalse(shouldRecover)
    }

    func testWarmedDirectPlaySelectionCanBeReusedForResume() {
        let selection = makeWarmedSelection(
            route: .directPlay(URL(string: "https://example.com/Videos/item/stream?static=true")!)
        )

        XCTAssertTrue(
            PlaybackSessionController.canUseWarmedSelection(selection, resumeSeconds: 1_039.7)
        )
    }

    func testWarmedTranscodeSelectionIsNotReusedForResume() {
        let selection = makeWarmedSelection(
            route: .transcode(URL(string: "https://example.com/videos/item/master.m3u8")!)
        )

        XCTAssertFalse(
            PlaybackSessionController.canUseWarmedSelection(selection, resumeSeconds: 1_039.7)
        )
    }

    func testWarmedTranscodeSelectionCanBeReusedFromBeginning() {
        let selection = makeWarmedSelection(
            route: .transcode(URL(string: "https://example.com/videos/item/master.m3u8")!)
        )

        XCTAssertTrue(
            PlaybackSessionController.canUseWarmedSelection(selection, resumeSeconds: 0)
        )
    }

    private func makeWarmedSelection(route: PlaybackRoute) -> PlaybackAssetSelection {
        let source = MediaSource(
            id: "source-1",
            itemID: "item-1",
            name: "Warm selection",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "aac",
            bitrate: 12_000_000,
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
        let assetURL: URL
        switch route {
        case .directPlay(let url), .remux(let url), .transcode(let url):
            assetURL = url
        case .nativeBridge:
            assetURL = URL(string: "https://example.com/nativebridge")!
        }

        return PlaybackAssetSelection(
            source: source,
            decision: PlaybackDecision(sourceID: source.id, route: route),
            assetURL: assetURL,
            headers: [:],
            debugInfo: PlaybackDebugInfo(
                container: source.container ?? "unknown",
                videoCodec: source.videoCodec ?? "unknown",
                videoBitDepth: source.videoBitDepth,
                hdrMode: .sdr,
                audioMode: source.audioCodec ?? "unknown",
                bitrate: source.bitrate,
                playMethod: PlaybackDecision(sourceID: source.id, route: route).playMethod
            )
        )
    }
}
