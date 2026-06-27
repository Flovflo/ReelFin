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

    func testPlaybackControlsModelExposesSingleAudioTrackAndSubtitleToggle() {
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
        XCTAssertEqual(model.audioOptions.map(\.trackID), ["audio-fr"])
        XCTAssertTrue(model.audioOptions.first?.isSelected == true)
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

    func testPremiumProgressiveDirectPlayUsesGuardedStartupBufferingOniOS() {
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

        XCTAssertEqual(policy.forwardBufferDuration, 30)
        XCTAssertTrue(policy.waitsToMinimizeStalling)
        XCTAssertEqual(policy.reason, "ios_guarded_directplay_startup")
    }

    func testHighBitrateProgressiveDirectPlayUsesGuardedStartupBufferingOniOS() {
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

        XCTAssertEqual(policy.forwardBufferDuration, 30)
        XCTAssertTrue(policy.waitsToMinimizeStalling)
        XCTAssertEqual(policy.reason, "ios_guarded_directplay_startup")
    }

    func testMeasuredHeadroomFastStartWaitsForDirectPlayItemReadyBeforeAutoplay() {
        let route = PlaybackRoute.directPlay(URL(string: "https://example.com/Videos/item-high-bitrate/stream.mp4?static=true&MediaSourceId=source")!)

        XCTAssertTrue(
            PlaybackSessionController.shouldWaitForItemReadyBeforeAutoplayAfterStartupSkip(
                route: route,
                itemStatus: .unknown
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldWaitForItemReadyBeforeAutoplayAfterStartupSkip(
                route: route,
                itemStatus: .readyToPlay
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldWaitForItemReadyBeforeAutoplayAfterStartupSkip(
                route: .transcode(URL(string: "https://example.com/videos/master.m3u8")!),
                itemStatus: .unknown
            )
        )
    }

    func testMeasuredHeadroomFastStartRestoresRemoteDirectPlaybackBuffering() {
        let policy = PlaybackSessionController.measuredHeadroomDirectPlayStartupPolicy(
            startupClass: .remoteDirect
        )

        XCTAssertEqual(policy.forwardBufferDuration, 2)
        XCTAssertFalse(policy.waitsToMinimizeStalling)
        XCTAssertEqual(policy.reason, "directplay_measured_headroom_fast_start")
    }

    func testIPhonePostStartDirectPlayStallKeepsAVPlayerWaitingMode() {
        XCTAssertTrue(
            DirectPlaySessionPolicy.postStartStallWaitsToMinimizeStalling(isTVOS: false)
        )
        XCTAssertTrue(
            DirectPlaySessionPolicy.postStartStallWaitsToMinimizeStalling(isTVOS: true)
        )
    }

    func testIPhonePostStartDirectPlayStallDoesNotPauseCurrentItem() {
        XCTAssertFalse(
            DirectPlaySessionPolicy.shouldPauseForPostStartStallRebuffer(isTVOS: false)
        )
        XCTAssertFalse(
            DirectPlaySessionPolicy.shouldPauseForPostStartStallRebuffer(isTVOS: true)
        )
    }

    func testHighBitrateProgressiveDirectPlayUsesGuardedStartupBufferingOnTvOS() {
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

        XCTAssertEqual(policy.forwardBufferDuration, 4)
        XCTAssertTrue(policy.waitsToMinimizeStalling)
        XCTAssertEqual(policy.reason, "tvos_guarded_directplay_startup")
    }

    func testPresentationSizeAloneDoesNotCountAsRenderedFrameWhenOutputIsAttached() {
        XCTAssertFalse(
            PlaybackSessionController.hasRenderableVideoFrame(
                copiedPixelBuffer: false,
                presentationSize: CGSize(width: 3840, height: 1608),
                videoOutputAttached: true,
                avkitReadyForDisplay: false,
                requiresAVKitReadyForDisplay: false
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
                requiresAVKitReadyForDisplay: false
            )
        )
    }

    func testIPhoneHDRDirectPlayRequiresAVKitReadyForDisplayBeforeRenderedFrameProof() {
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
            isTVOS: false
        ))
        XCTAssertFalse(
            PlaybackSessionController.hasRenderableVideoFrame(
                copiedPixelBuffer: true,
                presentationSize: CGSize(width: 3840, height: 1608),
                videoOutputAttached: true,
                avkitReadyForDisplay: false,
                requiresAVKitReadyForDisplay: true
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.hasRenderableVideoFrame(
                copiedPixelBuffer: true,
                presentationSize: CGSize(width: 3840, height: 1608),
                videoOutputAttached: true,
                avkitReadyForDisplay: true,
                requiresAVKitReadyForDisplay: true
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
                requiresAVKitReadyForDisplay: true
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.hasRenderableVideoFrame(
                copiedPixelBuffer: false,
                presentationSize: CGSize(width: 3840, height: 1608),
                videoOutputAttached: false,
                avkitReadyForDisplay: true,
                requiresAVKitReadyForDisplay: true
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

    func testPremiumProgressiveDirectPlayUsesGuardedStartupBufferingOnTvOS() {
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

        XCTAssertEqual(policy.forwardBufferDuration, 4)
        XCTAssertTrue(policy.waitsToMinimizeStalling)
        XCTAssertEqual(policy.reason, "tvos_guarded_directplay_startup")
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

    func testExtensionlessMP4DirectPlayAddsAVAssetMIMEOverride() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            filePath: "/media/Premium Movie.mp4",
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            videoCodec: "hvc1",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
        let url = URL(string: "https://example.com/Videos/premium-source/stream?static=true&MediaSourceId=premium-source")!
        let selection = makeSelection(source: source, route: .directPlay(url), assetURL: url)

        let options = PlaybackSessionController.avURLAssetOptions(
            for: selection,
            allowsCellularAccess: false
        )

        XCTAssertEqual(options[AVURLAssetOverrideMIMETypeKey] as? String, "video/mp4")
        XCTAssertNil(options[AVURLAssetAllowsCellularAccessKey])
    }

    func testProgressiveDirectPlayCountsAsAppleNativePlaybackPath() {
        XCTAssertTrue(
            PlaybackSessionController.isAppleNativePlaybackPath(
                playMethod: "DirectPlay",
                assetURL: URL(string: "http://127.0.0.1:65317/media/source.mp4")!
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.isAppleNativePlaybackPath(
                playMethod: "NativeBridge",
                assetURL: URL(string: "http://127.0.0.1:65317/media/source.mkv")!
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.isAppleNativePlaybackPath(
                playMethod: "Transcode",
                assetURL: URL(string: "https://example.com/Videos/item/master.m3u8")!
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.isAppleNativePlaybackPath(
                playMethod: "Transcode",
                assetURL: URL(string: "https://example.com/Videos/item/stream.mp4")!
            )
        )
    }

    func testPlaylistDirectPlayDoesNotAddAVAssetMIMEOverride() {
        let source = MediaSource(
            id: "playlist-source",
            itemID: "item-playlist",
            name: "Playlist stream",
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            bitrate: 6_000_000,
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
        let url = URL(string: "https://example.com/Videos/playlist-source/master.m3u8?static=true")!
        let selection = makeSelection(source: source, route: .directPlay(url), assetURL: url)

        let options = PlaybackSessionController.avURLAssetOptions(
            for: selection,
            allowsCellularAccess: false
        )

        XCTAssertNil(options[AVURLAssetOverrideMIMETypeKey])
    }

    func testDirectPlayResumeSeekIsDeferredUntilItemReady() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream?static=true&MediaSourceId=premium-source")!

        XCTAssertTrue(
            PlaybackSessionController.shouldDeferInitialDirectPlayResumeSeek(
                route: .directPlay(url),
                resumeSeconds: 1_225.3
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldDeferInitialDirectPlayResumeSeek(
                route: .directPlay(url),
                resumeSeconds: 0
            )
        )
    }

    func testReadyDirectPlayItemWithPendingResumeRequiresPreplaySeek() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream?static=true&MediaSourceId=premium-source")!

        XCTAssertTrue(
            PlaybackSessionController.shouldApplyPendingDirectPlayResumeSeekOnReady(
                route: .directPlay(url),
                pendingResumeSeconds: 1_590.071,
                currentTime: 0,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldApplyPendingDirectPlayResumeSeekOnReady(
                route: .directPlay(url),
                pendingResumeSeconds: 1_590.071,
                currentTime: 1_590.2,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldApplyPendingDirectPlayResumeSeekOnReady(
                route: .directPlay(url),
                pendingResumeSeconds: 1_590.071,
                currentTime: 0,
                itemStatus: .unknown,
                transcodeStartOffset: 0
            )
        )
    }

    func testItemReadyResumeSeekDefersToAutoplayStartupGate() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream?static=true&MediaSourceId=premium-source")!

        XCTAssertFalse(
            PlaybackSessionController.shouldApplyPendingDirectPlayResumeSeekOnReady(
                route: .directPlay(url),
                pendingResumeSeconds: 1_590.071,
                currentTime: 0,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                directPlayAutoplayStartupGateActive: true
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldApplyPendingDirectPlayResumeSeekOnReady(
                route: .directPlay(url),
                pendingResumeSeconds: 1_590.071,
                currentTime: 0,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                directPlayAutoplayStartupGateActive: false
            )
        )
    }

    func testAutoplayStartupGateOwnsDirectPlayResumeSeekOnlyForResumedDirectPlay() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream?static=true&MediaSourceId=premium-source")!

        XCTAssertTrue(
            PlaybackSessionController.shouldAutoplayStartupGateOwnDirectPlayResumeSeek(
                route: .directPlay(url),
                autoPlay: true,
                resumeSeconds: 1_590.071
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldAutoplayStartupGateOwnDirectPlayResumeSeek(
                route: .directPlay(url),
                autoPlay: false,
                resumeSeconds: 1_590.071
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldAutoplayStartupGateOwnDirectPlayResumeSeek(
                route: .directPlay(url),
                autoPlay: true,
                resumeSeconds: 0
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldAutoplayStartupGateOwnDirectPlayResumeSeek(
                route: .transcode(URL(string: "https://example.com/Videos/master.m3u8")!),
                autoPlay: true,
                resumeSeconds: 1_590.071
            )
        )
    }

    func testAutoplayStartupGateWaitsBrieflyForMaterializedDirectPlayResumeTime() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream?static=true&MediaSourceId=premium-source")!

        XCTAssertTrue(
            PlaybackSessionController.shouldWaitForMaterializedDirectPlayResumePositionBeforeStartupSeek(
                route: .directPlay(url),
                pendingResumeSeconds: 585.289,
                currentTime: 0,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                directPlayAutoplayStartupGateActive: true
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldWaitForMaterializedDirectPlayResumePositionBeforeStartupSeek(
                route: .directPlay(url),
                pendingResumeSeconds: 585.289,
                currentTime: 585.288,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                directPlayAutoplayStartupGateActive: true
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldWaitForMaterializedDirectPlayResumePositionBeforeStartupSeek(
                route: .directPlay(url),
                pendingResumeSeconds: 585.289,
                currentTime: 0,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                directPlayAutoplayStartupGateActive: false
            )
        )
    }

    func testAutoplayStartupGateWaitsLongEnoughForAVPlayerResumeMaterialization() {
        XCTAssertGreaterThanOrEqual(
            PlaybackSessionController.materializedDirectPlayResumePositionStartupWaitTimeout,
            2.0
        )
    }

    func testIPhonePremiumDirectPlayUsesLongNoStallStartupBuffer() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true")!
        let source = MediaSource(
            id: "premium-source",
            itemID: "premium-item",
            name: "Premium source",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 21_000_000,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            dvProfile: 8,
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let policy = PlaybackSessionController.directPlayStabilityPolicy(
            route: .directPlay(url),
            source: source,
            defaultForwardBufferDuration: 0,
            defaultWaitsToMinimizeStalling: false,
            maxStreamingBitrate: 100_000_000,
            isTVOS: false
        )

        XCTAssertEqual(policy.forwardBufferDuration, 30)
        XCTAssertTrue(policy.waitsToMinimizeStalling)
        XCTAssertEqual(policy.reason, "ios_guarded_directplay_startup")
    }

    func testStartupSubtitleSelectionReassertsDirectPlayResumeOnlyWhenPlaybackFallsBehindTarget() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream?static=true&MediaSourceId=premium-source")!
        let resumeSeconds = 2_128.126

        XCTAssertTrue(
            PlaybackSessionController.shouldReassertDirectPlayResumePositionAfterStartupSelection(
                route: .directPlay(url),
                resumeSeconds: resumeSeconds,
                currentTime: 1.261,
                transcodeStartOffset: 0
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldReassertDirectPlayResumePositionAfterStartupSelection(
                route: .directPlay(url),
                resumeSeconds: resumeSeconds,
                currentTime: 2_128.417,
                transcodeStartOffset: 0
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldReassertDirectPlayResumePositionAfterStartupSelection(
                route: .directPlay(url),
                resumeSeconds: resumeSeconds,
                currentTime: 2_133.417,
                transcodeStartOffset: 0
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldReassertDirectPlayResumePositionAfterStartupSelection(
                route: .directPlay(url),
                resumeSeconds: resumeSeconds,
                currentTime: 1.261,
                transcodeStartOffset: resumeSeconds
            )
        )
    }

    func testDirectPlaySameRouteRecoveryPreservesMissingResumeAsNil() {
        XCTAssertNil(
            PlaybackSessionController.directPlaySameRouteRecoveryResumeSeconds(
                hasMarkedFirstFrame: false,
                playerSeconds: 0,
                sessionInitialResumeSeconds: 0,
                transcodeStartOffset: 0
            )
        )
    }

    func testDirectPlaySameRouteRecoveryUsesPositiveResumeContext() {
        XCTAssertEqual(
            PlaybackSessionController.directPlaySameRouteRecoveryResumeSeconds(
                hasMarkedFirstFrame: false,
                playerSeconds: 0,
                sessionInitialResumeSeconds: 2_128.126,
                transcodeStartOffset: 0
            ),
            2_128.126
        )
        XCTAssertEqual(
            PlaybackSessionController.directPlaySameRouteRecoveryResumeSeconds(
                hasMarkedFirstFrame: true,
                playerSeconds: 12.5,
                sessionInitialResumeSeconds: 2_128.126,
                transcodeStartOffset: 100
            ),
            112.5
        )
    }

    func testVisibleDirectPlayFrameAtPendingResumeDoesNotBypassBufferedStartupReadiness() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream?static=true&MediaSourceId=premium-source")!

        XCTAssertFalse(
            PlaybackSessionController.shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
                route: .directPlay(url),
                hasMarkedFirstFrame: true,
                pendingResumeSeconds: 1_590.071,
                currentTime: 1_590.417,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
                route: .directPlay(url),
                hasMarkedFirstFrame: false,
                pendingResumeSeconds: 1_590.071,
                currentTime: 1_590.417,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
                route: .directPlay(url),
                hasMarkedFirstFrame: true,
                pendingResumeSeconds: 1_590.071,
                currentTime: 11.7,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
                route: .directPlay(url),
                hasMarkedFirstFrame: true,
                pendingResumeSeconds: 1_590.071,
                currentTime: 1_590.417,
                itemStatus: .unknown,
                transcodeStartOffset: 0
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
                route: .directPlay(url),
                hasMarkedFirstFrame: true,
                pendingResumeSeconds: nil,
                currentTime: 0,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0
            )
        )
    }

    func testActiveDirectPlayFrameAtPendingResumeSatisfiesStartupReadiness() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream?static=true&MediaSourceId=premium-source")!

        XCTAssertTrue(
            PlaybackSessionController.shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
                route: .directPlay(url),
                hasMarkedFirstFrame: true,
                pendingResumeSeconds: 1_590.071,
                currentTime: 1_590.417,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                isPlaybackActive: true
            )
        )
    }

    func testMaterializedDirectPlayResumeCanSatisfyPendingSeekCallback() {
        XCTAssertTrue(
            PlaybackSessionController.shouldAcceptMaterializedDirectPlayResumeSeek(
                currentTime: 549.350,
                resumeSeconds: 549.350,
                itemStatus: .readyToPlay,
                hasMarkedFirstFrame: true
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldAcceptMaterializedDirectPlayResumeSeek(
                currentTime: 0,
                resumeSeconds: 549.350,
                itemStatus: .readyToPlay,
                hasMarkedFirstFrame: true
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldAcceptMaterializedDirectPlayResumeSeek(
                currentTime: 549.350,
                resumeSeconds: 549.350,
                itemStatus: .readyToPlay,
                hasMarkedFirstFrame: false
            )
        )
    }

    func testPausedDirectPlayFrameCanReleaseStartupReadinessOnlyAfterHealthyNonZeroPreheat() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 77_000_000,
            rangeStart: 352_321_536,
            reason: "directplay_range_deep"
        )
        let zeroRangePreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 77_000_000,
            rangeStart: 0,
            reason: "directplay_range_deep"
        )

        XCTAssertTrue(
            PlaybackSessionController.shouldReleasePausedStartupAfterFirstFrame(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 0,
                preheatResult: healthyPreheat,
                serverBaselineResult: nil,
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldReleasePausedStartupAfterFirstFrame(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 1_590.071,
                preheatResult: healthyPreheat,
                serverBaselineResult: nil,
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldReleasePausedStartupAfterFirstFrame(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 0,
                preheatResult: zeroRangePreheat,
                serverBaselineResult: nil,
                isTVOS: false
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldTreatStartupReadinessAsSatisfiedAfterFirstFrame(
                route: .directPlay(url),
                hasMarkedFirstFrame: true,
                pendingResumeSeconds: 1_590.071,
                currentTime: 1_590.417,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                allowPausedDirectPlayFirstFrame: true
            )
        )
    }

    func testResumedSparseDirectPlayRequiresPlayerBufferWithHealthyPreheat() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 77_000_000,
            rangeStart: 352_321_536,
            reason: "directplay_range_deep"
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldReleaseSparseResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 1_590.071,
                hasMarkedFirstFrame: true,
                currentTime: 1_590.417,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                likelyToKeepUp: false,
                bufferedDuration: 0,
                bufferStableDuration: 0,
                preheatResult: healthyPreheat,
                accessObservedBitrate: nil,
                accessStallCount: nil,
                selectedAudioTrackID: "track-2",
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldReleaseSparseResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 1_590.071,
                hasMarkedFirstFrame: true,
                currentTime: 1_590.417,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                likelyToKeepUp: true,
                bufferedDuration: 20.1,
                bufferStableDuration: 0.4,
                preheatResult: healthyPreheat,
                accessObservedBitrate: nil,
                accessStallCount: nil,
                selectedAudioTrackID: "track-2",
                isTVOS: false
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldReleaseSparseResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 1_590.071,
                hasMarkedFirstFrame: true,
                currentTime: 1_590.417,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                likelyToKeepUp: true,
                bufferedDuration: 20.1,
                bufferStableDuration: 2.1,
                preheatResult: healthyPreheat,
                accessObservedBitrate: nil,
                accessStallCount: nil,
                selectedAudioTrackID: "track-2",
                isTVOS: false
            )
        )
    }

    func testIPhoneStrictDirectPlayStartupRequiresStableBufferWindow() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 20,
            preferredBufferDuration: 30,
            timeout: 45,
            pollInterval: 0.15,
            reason: "ios_hdr_dv_resume_directplay_ready",
            allowsTimeoutStart: false
        )

        XCTAssertTrue(
            PlaybackSessionController.requiresStableStartupReadinessBuffer(
                route: .directPlay(url),
                source: premiumDirectPlaySource(),
                requirement: requirement,
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.hasStableStartupReadinessBuffer(
                bufferedDuration: 24,
                likelyToKeepUp: true,
                stableDuration: 0.5
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.hasStableStartupReadinessBuffer(
                bufferedDuration: 24,
                likelyToKeepUp: true,
                stableDuration: 2.1
            )
        )
    }

    func testBufferedDurationAheadIgnoresRangesBeforeResumePosition() {
        let startupRange = CMTimeRange(
            start: CMTime(seconds: 0, preferredTimescale: 600),
            duration: CMTime(seconds: 24.3, preferredTimescale: 600)
        )
        let resumeRange = CMTimeRange(
            start: CMTime(seconds: 549.0, preferredTimescale: 600),
            duration: CMTime(seconds: 24.3, preferredTimescale: 600)
        )

        XCTAssertEqual(
            PlaybackSessionController.bufferedDurationAhead(
                playbackPosition: 549.35,
                loadedTimeRanges: [startupRange]
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PlaybackSessionController.bufferedDurationAhead(
                playbackPosition: 549.35,
                loadedTimeRanges: [resumeRange]
            ),
            23.95,
            accuracy: 0.001
        )
    }

    func testResumedSparseDirectPlayRequiresNonZeroRangeAudioAndHeadroom() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 77_000_000,
            rangeStart: 352_321_536,
            reason: "directplay_range_deep"
        )
        let zeroRangePreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 77_000_000,
            rangeStart: 0,
            reason: "directplay_range_deep"
        )
        let weakPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 18_000_000,
            rangeStart: 352_321_536,
            reason: "directplay_range_deep"
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldReleaseSparseResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 1_590.071,
                hasMarkedFirstFrame: true,
                currentTime: 1_590.417,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                likelyToKeepUp: false,
                bufferedDuration: 0,
                bufferStableDuration: 0,
                preheatResult: zeroRangePreheat,
                accessObservedBitrate: nil,
                accessStallCount: nil,
                selectedAudioTrackID: "track-2",
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldReleaseSparseResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 1_590.071,
                hasMarkedFirstFrame: true,
                currentTime: 1_590.417,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                likelyToKeepUp: false,
                bufferedDuration: 0,
                bufferStableDuration: 0,
                preheatResult: weakPreheat,
                accessObservedBitrate: nil,
                accessStallCount: nil,
                selectedAudioTrackID: "track-2",
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldReleaseSparseResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 1_590.071,
                hasMarkedFirstFrame: true,
                currentTime: 1_590.417,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                likelyToKeepUp: true,
                bufferedDuration: 7,
                bufferStableDuration: 2.1,
                preheatResult: healthyPreheat,
                accessObservedBitrate: 47_000_000,
                accessStallCount: 0,
                selectedAudioTrackID: nil,
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldReleaseSparseResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 1_590.071,
                hasMarkedFirstFrame: true,
                currentTime: 1_590.417,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                likelyToKeepUp: true,
                bufferedDuration: 7,
                bufferStableDuration: 2.1,
                preheatResult: healthyPreheat,
                accessObservedBitrate: 47_000_000,
                accessStallCount: 1,
                selectedAudioTrackID: "track-2",
                isTVOS: false
            )
        )
    }

    func testResumedSparseDirectPlayCanUseHealthyAccessLogEvidence() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!

        XCTAssertTrue(
            PlaybackSessionController.shouldReleaseSparseResumedDirectPlayStartup(
                route: .directPlay(url),
                source: premiumDirectPlaySource(),
                resumeSeconds: 1_590.071,
                hasMarkedFirstFrame: true,
                currentTime: 1_590.417,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                likelyToKeepUp: true,
                bufferedDuration: 20.1,
                bufferStableDuration: 2.1,
                preheatResult: nil,
                accessObservedBitrate: 47_000_000,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                isTVOS: false
            )
        )
    }

    func testResumedDirectPlayGatewayRequiresCachedNonZeroStartupWindow() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 77_000_000,
            rangeStart: 352_321_536,
            reason: "directplay_range_deep"
        )
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 20,
            preferredBufferDuration: 30,
            timeout: 45,
            pollInterval: 0.15,
            reason: "ios_hdr_dv_resume_directplay_ready",
            allowsTimeoutStart: false
        )
        let requiredBytes = Int64(Double(source.bitrate ?? 0) * requirement.minimumBufferDuration / 8)
        let weakGateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 8_351_503_198,
            observedBitrate: 77_000_000,
            cachedBytes: requiredBytes / 2,
            largestNonZeroCachedOffset: healthyPreheat.rangeStart,
            largestNonZeroCachedRangeLength: requiredBytes / 2,
            latestNonZeroCachedOffset: healthyPreheat.rangeStart,
            latestNonZeroCachedRangeLength: requiredBytes / 2,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: healthyPreheat.rangeStart ?? 0, length: requiredBytes / 2)
            ]
        )
        let healthyGateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 8_351_503_198,
            observedBitrate: 77_000_000,
            cachedBytes: requiredBytes + 1,
            largestNonZeroCachedOffset: healthyPreheat.rangeStart,
            largestNonZeroCachedRangeLength: requiredBytes + 1,
            latestNonZeroCachedOffset: healthyPreheat.rangeStart,
            latestNonZeroCachedRangeLength: requiredBytes + 1,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: healthyPreheat.rangeStart ?? 0, length: requiredBytes + 1)
            ]
        )
        let earlyMetadataGateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 8_351_503_198,
            observedBitrate: 77_000_000,
            cachedBytes: requiredBytes + 1,
            largestNonZeroCachedOffset: 20_250_624,
            largestNonZeroCachedRangeLength: requiredBytes + 1,
            latestNonZeroCachedOffset: 20_250_624,
            latestNonZeroCachedRangeLength: requiredBytes + 1,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: 20_250_624, length: requiredBytes + 1)
            ]
        )
        let mixedMetadataAndPlaybackGateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 8_351_503_198,
            observedBitrate: 77_000_000,
            cachedBytes: requiredBytes + 65_536,
            largestNonZeroCachedOffset: 20_250_624,
            largestNonZeroCachedRangeLength: requiredBytes + 1,
            latestNonZeroCachedOffset: 482_279_424,
            latestNonZeroCachedRangeLength: 65_536,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: 20_250_624, length: requiredBytes + 1),
                LocalMediaGatewayCachedRange(offset: 482_279_424, length: 65_536)
            ]
        )
        let farAheadGateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 8_351_503_198,
            observedBitrate: 77_000_000,
            cachedBytes: requiredBytes + 1,
            largestNonZeroCachedOffset: 1_554_395_952,
            largestNonZeroCachedRangeLength: requiredBytes + 1,
            latestNonZeroCachedOffset: 1_554_395_952,
            latestNonZeroCachedRangeLength: requiredBytes + 1,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: 1_554_395_952, length: requiredBytes + 1)
            ]
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldReleaseLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 549.350,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: true,
                bufferedDuration: 20.1,
                bufferStableDuration: 2.1,
                accessObservedBitrate: nil,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: weakGateway,
                requirement: requirement,
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldReleaseLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 549.350,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: false,
                bufferedDuration: 20.1,
                bufferStableDuration: 2.1,
                accessObservedBitrate: nil,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: healthyGateway,
                requirement: requirement,
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldReleaseLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 549.350,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: true,
                bufferedDuration: 20.1,
                bufferStableDuration: 2.1,
                accessObservedBitrate: nil,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: farAheadGateway,
                requirement: requirement,
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldReleaseLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 549.350,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: true,
                bufferedDuration: 20.1,
                bufferStableDuration: 2.1,
                accessObservedBitrate: nil,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: earlyMetadataGateway,
                requirement: requirement,
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldReleaseLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 549.350,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: true,
                bufferedDuration: 20.1,
                bufferStableDuration: 2.1,
                accessObservedBitrate: nil,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: mixedMetadataAndPlaybackGateway,
                requirement: requirement,
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldReleaseLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 549.350,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: true,
                bufferedDuration: 4,
                bufferStableDuration: 2.1,
                accessObservedBitrate: nil,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: healthyGateway,
                requirement: requirement,
                isTVOS: false
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldReleaseLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 549.350,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: true,
                bufferedDuration: 20.1,
                bufferStableDuration: 0.4,
                accessObservedBitrate: nil,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: healthyGateway,
                requirement: requirement,
                isTVOS: false
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldReleaseLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 549.350,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: true,
                bufferedDuration: 20.1,
                bufferStableDuration: 2.1,
                accessObservedBitrate: nil,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: healthyGateway,
                requirement: requirement,
                isTVOS: false
            )
        )
    }

    func testResumedDirectPlayGatewayRejectsCacheOnlyWithoutMaterializedBuffer() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 77_000_000,
            rangeStart: 545_259_520,
            reason: "directplay_range_deep"
        )
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 20,
            preferredBufferDuration: 30,
            timeout: 45,
            pollInterval: 0.15,
            reason: "ios_hdr_dv_resume_directplay_ready",
            allowsTimeoutStart: false
        )
        let requiredBytes = Int64(Double(source.bitrate ?? 0) * requirement.minimumBufferDuration / 8)
        let gateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 8_351_503_198,
            observedBitrate: 77_000_000,
            cachedBytes: requiredBytes + 1,
            largestNonZeroCachedOffset: healthyPreheat.rangeStart,
            largestNonZeroCachedRangeLength: requiredBytes + 1,
            latestNonZeroCachedOffset: healthyPreheat.rangeStart,
            latestNonZeroCachedRangeLength: requiredBytes + 1,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: healthyPreheat.rangeStart ?? 0, length: requiredBytes + 1)
            ]
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldReleaseLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 549.350,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: true,
                bufferedDuration: 0,
                bufferStableDuration: 0,
                accessObservedBitrate: 194_000_000,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: gateway,
                requirement: requirement,
                isTVOS: false
            )
        )
    }

    func testResumedDirectPlayGatewayAcceptsNearbyCacheWithMaterializedBuffer() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 77_000_000,
            rangeStart: 545_259_520,
            reason: "directplay_range_deep"
        )
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 20,
            preferredBufferDuration: 30,
            timeout: 45,
            pollInterval: 0.15,
            reason: "ios_hdr_dv_resume_directplay_ready",
            allowsTimeoutStart: false
        )
        let requiredBytes = Int64(Double(source.bitrate ?? 0) * requirement.minimumBufferDuration / 8)
        let nearbyGateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 8_351_503_198,
            observedBitrate: 77_000_000,
            cachedBytes: requiredBytes + 1,
            largestNonZeroCachedOffset: 482_279_424,
            largestNonZeroCachedRangeLength: requiredBytes + 1,
            latestNonZeroCachedOffset: 482_279_424,
            latestNonZeroCachedRangeLength: requiredBytes + 1,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: 482_279_424, length: requiredBytes + 1)
            ]
        )

        XCTAssertTrue(
            PlaybackSessionController.shouldReleaseLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 549.350,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: true,
                bufferedDuration: 6.1,
                bufferStableDuration: 0,
                accessObservedBitrate: 49_000_000,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: nearbyGateway,
                requirement: requirement,
                isTVOS: false
            )
        )
    }

    func testResumedDirectPlayGatewayWaitsForActiveStreamingPrefetchWindow() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 77_000_000,
            rangeStart: 545_259_520,
            reason: "directplay_range_deep"
        )
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 20,
            preferredBufferDuration: 30,
            timeout: 45,
            pollInterval: 0.15,
            reason: "ios_hdr_dv_resume_directplay_ready",
            allowsTimeoutStart: false
        )
        let requiredBytes = Int64(Double(source.bitrate ?? 0) * requirement.minimumBufferDuration / 8)
        let nearbyRange = LocalMediaGatewayCachedRange(offset: 482_279_424, length: requiredBytes + 1)
        let activeRange = LocalMediaGatewayCachedRange(offset: 168_624_128, length: requiredBytes + 1)
        let incompleteActiveGateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 8_351_503_198,
            observedBitrate: 77_000_000,
            cachedBytes: requiredBytes + 1,
            largestNonZeroCachedOffset: nearbyRange.offset,
            largestNonZeroCachedRangeLength: nearbyRange.length,
            latestNonZeroCachedOffset: nearbyRange.offset,
            latestNonZeroCachedRangeLength: nearbyRange.length,
            nonZeroCachedRanges: [nearbyRange],
            activePrefetchStartOffset: activeRange.offset,
            activePrefetchEndOffset: activeRange.offset + activeRange.length,
            activePrefetchIsStreamingPlayback: true
        )
        let completeActiveGateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 8_351_503_198,
            observedBitrate: 77_000_000,
            cachedBytes: (requiredBytes + 1) * 2,
            largestNonZeroCachedOffset: nearbyRange.offset,
            largestNonZeroCachedRangeLength: nearbyRange.length,
            latestNonZeroCachedOffset: nearbyRange.offset,
            latestNonZeroCachedRangeLength: nearbyRange.length,
            nonZeroCachedRanges: [activeRange, nearbyRange],
            activePrefetchStartOffset: activeRange.offset,
            activePrefetchEndOffset: activeRange.offset + activeRange.length,
            activePrefetchIsStreamingPlayback: true
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldReleaseLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 549.350,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: true,
                bufferedDuration: 6.1,
                bufferStableDuration: 0,
                accessObservedBitrate: 49_000_000,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: incompleteActiveGateway,
                requirement: requirement,
                isTVOS: false
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldReleaseLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 549.350,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: true,
                bufferedDuration: 6.1,
                bufferStableDuration: 0,
                accessObservedBitrate: 49_000_000,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: completeActiveGateway,
                requirement: requirement,
                isTVOS: false
            )
        )
    }

    func testLocalGatewayReadinessPrimesPlaybackWhenPausedBufferCannotMaterialize() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 84_000_000,
            rangeStart: 1_497_366_528,
            reason: "directplay_range_deep"
        )
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 20,
            preferredBufferDuration: 30,
            timeout: 45,
            pollInterval: 0.15,
            reason: "ios_hdr_dv_resume_directplay_ready",
            allowsTimeoutStart: false
        )
        let gateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 17_693_312_645,
            observedBitrate: 54_000_000,
            cachedBytes: 120 * 1_024 * 1_024,
            largestNonZeroCachedOffset: 1_638_203_392,
            largestNonZeroCachedRangeLength: 120 * 1_024 * 1_024,
            latestNonZeroCachedOffset: 1_638_203_392,
            latestNonZeroCachedRangeLength: 120 * 1_024 * 1_024,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: 1_638_203_392, length: 120 * 1_024 * 1_024)
            ]
        )

        XCTAssertTrue(
            PlaybackSessionController.shouldPrimeLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 548.500,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                bufferedDuration: 0.4,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: gateway,
                requirement: requirement,
                isTVOS: false
            )
        )
    }

    func testLocalGatewayReadinessDoesNotPrimePlaybackWithOnlyProbeCache() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 84_000_000,
            rangeStart: 1_497_366_528,
            reason: "directplay_range_deep"
        )
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 20,
            preferredBufferDuration: 30,
            timeout: 45,
            pollInterval: 0.15,
            reason: "ios_hdr_dv_resume_directplay_ready",
            allowsTimeoutStart: false
        )
        let gateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 17_693_312_645,
            observedBitrate: 54_000_000,
            cachedBytes: 32 * 1_024 * 1_024,
            largestNonZeroCachedOffset: healthyPreheat.rangeStart,
            largestNonZeroCachedRangeLength: 32 * 1_024 * 1_024,
            latestNonZeroCachedOffset: healthyPreheat.rangeStart,
            latestNonZeroCachedRangeLength: 32 * 1_024 * 1_024,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: healthyPreheat.rangeStart ?? 0, length: 32 * 1_024 * 1_024)
            ]
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldPrimeLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 548.500,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                bufferedDuration: 0.4,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: gateway,
                requirement: requirement,
                isTVOS: false
            )
        )
    }

    func testLocalGatewayReadinessPrimesWhenGatewayHasAggregateMomentum() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 84_000_000,
            rangeStart: 1_497_366_528,
            reason: "directplay_range_deep"
        )
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 20,
            preferredBufferDuration: 30,
            timeout: 45,
            pollInterval: 0.15,
            reason: "ios_hdr_dv_resume_directplay_ready",
            allowsTimeoutStart: false
        )
        let gateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 17_693_312_645,
            observedBitrate: 62_000_000,
            cachedBytes: 96 * 1_024 * 1_024,
            largestNonZeroCachedOffset: 524_290,
            largestNonZeroCachedRangeLength: 96 * 1_024 * 1_024,
            latestNonZeroCachedOffset: 15_543_959_552,
            latestNonZeroCachedRangeLength: 4 * 1_024 * 1_024,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: 524_290, length: 96 * 1_024 * 1_024),
                LocalMediaGatewayCachedRange(offset: 15_543_959_552, length: 4 * 1_024 * 1_024)
            ]
        )

        XCTAssertTrue(
            PlaybackSessionController.shouldPrimeLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 548.500,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                bufferedDuration: 0.4,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: gateway,
                requirement: requirement,
                isTVOS: false
            )
        )
    }

    func testLocalGatewayReadinessPrimesWhenActiveStreamingPrefetchNeedsPlayback() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 84_000_000,
            rangeStart: 545_259_520,
            reason: "directplay_range_deep"
        )
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 20,
            preferredBufferDuration: 30,
            timeout: 45,
            pollInterval: 0.15,
            reason: "ios_hdr_dv_resume_directplay_ready",
            allowsTimeoutStart: false
        )
        let gateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 8_351_503_198,
            observedBitrate: 77_000_000,
            cachedBytes: 16 * 1_024 * 1_024,
            largestNonZeroCachedOffset: 524_290,
            largestNonZeroCachedRangeLength: 16 * 1_024 * 1_024,
            latestNonZeroCachedOffset: 482_279_424,
            latestNonZeroCachedRangeLength: 1 * 1_024 * 1_024,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: 524_290, length: 16 * 1_024 * 1_024),
                LocalMediaGatewayCachedRange(offset: 482_279_424, length: 1 * 1_024 * 1_024)
            ],
            activePrefetchStartOffset: 168_624_128,
            activePrefetchEndOffset: 340_000_000,
            activePrefetchIsStreamingPlayback: true
        )

        XCTAssertTrue(
            PlaybackSessionController.shouldPrimeLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 549.350,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                bufferedDuration: 0.0,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: gateway,
                requirement: requirement,
                isTVOS: false
            )
        )
    }

    func testLocalGatewayPrimedPlaybackRequiresRealProgressBeforeReadinessRelease() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 84_000_000,
            rangeStart: 1_497_366_528,
            reason: "directplay_range_deep"
        )
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 20,
            preferredBufferDuration: 30,
            timeout: 45,
            pollInterval: 0.15,
            reason: "ios_hdr_dv_resume_directplay_ready",
            allowsTimeoutStart: false
        )
        let gateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 17_693_312_645,
            observedBitrate: 54_000_000,
            cachedBytes: 120 * 1_024 * 1_024,
            largestNonZeroCachedOffset: 1_638_203_392,
            largestNonZeroCachedRangeLength: 120 * 1_024 * 1_024,
            latestNonZeroCachedOffset: 1_638_203_392,
            latestNonZeroCachedRangeLength: 120 * 1_024 * 1_024,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: 1_638_203_392, length: 120 * 1_024 * 1_024)
            ]
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldReleasePrimedLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                primingStartTime: 548.500,
                hasMarkedFirstFrame: true,
                currentTime: 549.100,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: true,
                bufferedDuration: 1.1,
                accessObservedBitrate: 130_000_000,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: gateway,
                requirement: requirement,
                isTVOS: false
            )
        )
    }

    func testLocalGatewayPrimedPlaybackCanReleaseAfterProgressWithSmallBuffer() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 84_000_000,
            rangeStart: 1_497_366_528,
            reason: "directplay_range_deep"
        )
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 20,
            preferredBufferDuration: 30,
            timeout: 45,
            pollInterval: 0.15,
            reason: "ios_hdr_dv_resume_directplay_ready",
            allowsTimeoutStart: false
        )
        let gateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 17_693_312_645,
            observedBitrate: 54_000_000,
            cachedBytes: 120 * 1_024 * 1_024,
            largestNonZeroCachedOffset: 1_638_203_392,
            largestNonZeroCachedRangeLength: 120 * 1_024 * 1_024,
            latestNonZeroCachedOffset: 1_638_203_392,
            latestNonZeroCachedRangeLength: 120 * 1_024 * 1_024,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: 1_638_203_392, length: 120 * 1_024 * 1_024)
            ]
        )

        XCTAssertTrue(
            PlaybackSessionController.shouldReleasePrimedLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                primingStartTime: 548.500,
                hasMarkedFirstFrame: true,
                currentTime: 557.000,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: true,
                bufferedDuration: 1.1,
                accessObservedBitrate: 130_000_000,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: gateway,
                requirement: requirement,
                isTVOS: false
            )
        )
    }

    func testLocalGatewayPrimedPlaybackCanReleaseOnProgressWhileActiveWindowFills() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 84_000_000,
            rangeStart: 545_259_520,
            reason: "directplay_range_deep"
        )
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 20,
            preferredBufferDuration: 30,
            timeout: 45,
            pollInterval: 0.15,
            reason: "ios_hdr_dv_resume_directplay_ready",
            allowsTimeoutStart: false
        )
        let gateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 8_351_503_198,
            observedBitrate: 77_000_000,
            cachedBytes: 64 * 1_024 * 1_024,
            largestNonZeroCachedOffset: 524_290,
            largestNonZeroCachedRangeLength: 64 * 1_024 * 1_024,
            latestNonZeroCachedOffset: 482_279_424,
            latestNonZeroCachedRangeLength: 4 * 1_024 * 1_024,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: 524_290, length: 64 * 1_024 * 1_024),
                LocalMediaGatewayCachedRange(offset: 482_279_424, length: 4 * 1_024 * 1_024)
            ],
            activePrefetchStartOffset: 168_624_128,
            activePrefetchEndOffset: 340_000_000,
            activePrefetchIsStreamingPlayback: true
        )

        XCTAssertTrue(
            PlaybackSessionController.shouldReleasePrimedLocalGatewayResumedDirectPlayStartup(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                primingStartTime: 549.350,
                hasMarkedFirstFrame: true,
                currentTime: 558.000,
                itemStatus: .readyToPlay,
                transcodeStartOffset: 0,
                preheatResult: healthyPreheat,
                likelyToKeepUp: true,
                bufferedDuration: 1.1,
                accessObservedBitrate: 120_000_000,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: gateway,
                requirement: requirement,
                isTVOS: false
            )
        )
    }

    func testLocalGatewayPrimingPlaybackPausesBeforeConsumingSparseBuffer() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()

        XCTAssertFalse(
            PlaybackSessionController.shouldPauseLocalGatewayPrimingPlayback(
                route: .directPlay(url),
                source: source,
                primingStartTime: 548.500,
                currentTime: 548.900,
                bufferedDuration: 0.4,
                isTVOS: false
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldPauseLocalGatewayPrimingPlayback(
                route: .directPlay(url),
                source: source,
                primingStartTime: 548.500,
                currentTime: 549.400,
                bufferedDuration: 0.4,
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldPauseLocalGatewayPrimingPlayback(
                route: .directPlay(url),
                source: source,
                primingStartTime: 548.500,
                currentTime: 549.400,
                bufferedDuration: 6.1,
                isTVOS: false
            )
        )
    }

    func testLocalGatewayPrimingKeepsPlayingWhileActiveStreamingWindowFills() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let gateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 8_351_503_198,
            observedBitrate: 77_000_000,
            cachedBytes: 24 * 1_024 * 1_024,
            largestNonZeroCachedOffset: 524_290,
            largestNonZeroCachedRangeLength: 24 * 1_024 * 1_024,
            latestNonZeroCachedOffset: 482_279_424,
            latestNonZeroCachedRangeLength: 1 * 1_024 * 1_024,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: 524_290, length: 24 * 1_024 * 1_024),
                LocalMediaGatewayCachedRange(offset: 482_279_424, length: 1 * 1_024 * 1_024)
            ],
            activePrefetchStartOffset: 168_624_128,
            activePrefetchEndOffset: 340_000_000,
            activePrefetchIsStreamingPlayback: true
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldPauseLocalGatewayPrimingPlayback(
                route: .directPlay(url),
                source: source,
                primingStartTime: 549.350,
                currentTime: 550.000,
                bufferedDuration: 0.0,
                gatewayDiagnostics: gateway,
                isTVOS: false
            )
        )
    }

    func testLocalGatewayPrimingPlaybackResumesOnlyAfterHealthyGatewayWindow() {
        let url = URL(string: "https://example.com/Videos/premium-source/stream.mp4?static=true&MediaSourceId=premium-source")!
        let source = premiumDirectPlaySource()
        let healthyPreheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.3,
            observedBitrate: 84_000_000,
            rangeStart: 1_497_366_528,
            reason: "directplay_range_deep"
        )
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 20,
            preferredBufferDuration: 30,
            timeout: 45,
            pollInterval: 0.15,
            reason: "ios_hdr_dv_resume_directplay_ready",
            allowsTimeoutStart: false
        )
        let gateway = LocalMediaGatewayDiagnostics(
            contentType: "video/mp4",
            totalLength: 17_693_312_645,
            observedBitrate: 54_000_000,
            cachedBytes: 120 * 1_024 * 1_024,
            largestNonZeroCachedOffset: 1_638_203_392,
            largestNonZeroCachedRangeLength: 120 * 1_024 * 1_024,
            latestNonZeroCachedOffset: 1_638_203_392,
            latestNonZeroCachedRangeLength: 120 * 1_024 * 1_024,
            nonZeroCachedRanges: [
                LocalMediaGatewayCachedRange(offset: 1_638_203_392, length: 120 * 1_024 * 1_024)
            ]
        )

        XCTAssertTrue(
            PlaybackSessionController.shouldResumeLocalGatewayPrimingPlayback(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                currentTime: 549.100,
                preheatResult: healthyPreheat,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: gateway,
                requirement: requirement,
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldResumeLocalGatewayPrimingPlayback(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                currentTime: 549.100,
                preheatResult: healthyPreheat,
                accessStallCount: 1,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: gateway,
                requirement: requirement,
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldResumeLocalGatewayPrimingPlayback(
                route: .directPlay(url),
                source: source,
                resumeSeconds: 549.350,
                currentTime: 549.100,
                preheatResult: healthyPreheat,
                accessStallCount: 0,
                selectedAudioTrackID: "track-2",
                gatewayDiagnostics: nil,
                requirement: requirement,
                isTVOS: false
            )
        )
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

    func testIPhoneSinglePostFirstFrameDirectPlayStallKeepsCurrentItem() {
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
            elapsedSecondsSinceLoad: 15,
            elapsedSecondsSinceFirstFrame: 2
        )

        XCTAssertFalse(shouldRecover)
        XCTAssertTrue(
            PlaybackSessionController.shouldKeepCurrentDirectPlayItemAfterPostStartStall(
                route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
                source: source,
                isTVOS: false
            )
        )
        XCTAssertEqual(
            PlaybackSessionController.postStartDirectPlayStallBufferDuration(
                currentForwardBufferDuration: 12
            ),
            24
        )
    }

    func testIPhoneRepeatedPostFirstFrameDirectPlayStallsKeepCurrentItem() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let shouldRecover = PlaybackSessionController.shouldAttemptDirectPlayStallRecovery(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            recentStallCount: 3,
            elapsedSecondsSinceLoad: 26,
            elapsedSecondsSinceFirstFrame: 22
        )

        XCTAssertFalse(shouldRecover)
        XCTAssertTrue(
            PlaybackSessionController.shouldKeepCurrentDirectPlayItemAfterPostStartStall(
                route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
                source: source,
                isTVOS: false
            )
        )
    }

    func testRepeatedPostFirstFrameDirectPlayStallsMarkRouteFragileForFutureStarts() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let url = URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!
        // RAPID stalling (>= 3 in the 12 s window) LATE after the first frame → escalate.
        XCTAssertTrue(
            PlaybackSessionController.shouldMarkDirectPlayRouteFragileAfterPostStartStall(
                route: .directPlay(url), source: source, recentStallCount: 3, elapsedSecondsSinceFirstFrame: 22))
        // EARLY stall (couldn't sustain even the opening ~12 s) → connection can't carry the source
        // bitrate → escalate to watchable SDR on the FIRST stall (no point re-buffering DV that
        // re-stalls; device: stall at 6 s on a 17 Mbps link vs 26 Mbps source).
        XCTAssertTrue(
            PlaybackSessionController.shouldMarkDirectPlayRouteFragileAfterPostStartStall(
                route: .directPlay(url), source: source, recentStallCount: 1, elapsedSecondsSinceFirstFrame: 6))
        // A LATE single/double stall is usually a transient blip — ride it out on DV, do not escalate.
        XCTAssertFalse(
            PlaybackSessionController.shouldMarkDirectPlayRouteFragileAfterPostStartStall(
                route: .directPlay(url), source: source, recentStallCount: 1, elapsedSecondsSinceFirstFrame: 30))
        XCTAssertFalse(
            PlaybackSessionController.shouldMarkDirectPlayRouteFragileAfterPostStartStall(
                route: .directPlay(url), source: source, recentStallCount: 2, elapsedSecondsSinceFirstFrame: 30))
        // Still NOT fragile before the first frame (startup readiness handles that phase).
        XCTAssertFalse(
            PlaybackSessionController.shouldMarkDirectPlayRouteFragileAfterPostStartStall(
                route: .directPlay(url), source: source, recentStallCount: 3, elapsedSecondsSinceFirstFrame: nil))
    }

    func testIPhoneRepeatedLatePostFirstFrameDirectPlayStallsKeepCurrentItem() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let shouldRecover = PlaybackSessionController.shouldAttemptDirectPlayStallRecovery(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            recentStallCount: 3,
            elapsedSecondsSinceLoad: 189,
            elapsedSecondsSinceFirstFrame: 185
        )

        XCTAssertFalse(shouldRecover)
    }

    func testTvOSPostFirstFrameDirectPlayStallsKeepCurrentItemAndGrowBuffer() {
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
            elapsedSecondsSinceFirstFrame: 2,
            isTVOS: true
        )

        XCTAssertFalse(shouldRecover)
        XCTAssertTrue(
            PlaybackSessionController.shouldKeepCurrentDirectPlayItemAfterPostStartStall(
                route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
                source: source,
                isTVOS: true
            )
        )
        XCTAssertEqual(
            PlaybackSessionController.postStartDirectPlayStallBufferDuration(
                currentForwardBufferDuration: 24,
                recentStallCount: 3,
                isTVOS: true
            ),
            120
        )
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

    func testSingleDirectPlayStallRightAfterFirstFrameDoesNotTriggerRecovery() {
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

        XCTAssertFalse(shouldRecover)
    }

    func testPostStartDirectPlayStallKeepsDirectPlayWithoutProfileFallback() {
        // Adaptive fallback (user-approved): a sustained post-start stall now escalates to a
        // sustainable HLS transcode (never freeze) instead of keeping the frozen direct-play item.
        // When the flag is off, the original "keep direct play, no fallback" policy holds.
        XCTAssertEqual(
            PlaybackSessionController.shouldDisableDirectRoutesForRecovery(
                reason: StartupFailureReason.directPlayPostStartStall.rawValue
            ),
            AdaptiveFallbackPolicy.isEnabled
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldSuspendCurrentItemBeforeProfileRecovery(
                reason: StartupFailureReason.directPlayPostStartStall.rawValue
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldAttemptSameRouteDirectPlayRecovery(
                reason: StartupFailureReason.directPlayPostStartStall.rawValue
            )
        )
        XCTAssertEqual(
            PlaybackSessionController.shouldAllowNativeModeCoordinatorFallback(
                reason: StartupFailureReason.directPlayPostStartStall.rawValue
            ),
            AdaptiveFallbackPolicy.isEnabled
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldAllowNativeModeCoordinatorFallback(
                reason: StartupFailureReason.decodedFrameWatchdog.rawValue
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldAllowNativeModeCoordinatorFallback(
                reason: StartupFailureReason.decodedFrameWatchdog.rawValue,
                rootReason: StartupFailureReason.directPlayPostStartStall.rawValue
            )
        )
        XCTAssertFalse(StartupFailureReason.directPlayPostStartStall.shouldTriggerRecovery)
    }

    func testPostFirstFrameDirectPlayItemFailureIsNotSuppressed() {
        let route = PlaybackRoute.directPlay(
            URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldSuppressPlaybackFailureRecoveryAfterFirstFrame(
                hasMarkedFirstFrame: true,
                route: route
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldAttemptSameRouteDirectPlayRecovery(
                reason: StartupFailureReason.playerItemFailedTransient.rawValue
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldSuppressPlaybackFailureRecoveryAfterFirstFrame(
                hasMarkedFirstFrame: true,
                route: .transcode(URL(string: "https://example.com/Videos/item/master.m3u8")!)
            )
        )
    }

    func testGatewayRecoveryUnwrapsLocalSelectionToOriginalRemoteSelection() {
        let remoteURL = URL(string: "https://media.example.com/Videos/item/stream.mp4?static=true&api_key=secret")!
        let localURL = URL(string: "http://127.0.0.1:59235/media/session")!
        var remoteSelection = makeWarmedSelection(route: .directPlay(remoteURL))
        remoteSelection.assetURL = remoteURL
        remoteSelection.headers = ["X-Emby-Token": "secret"]
        var localSelection = remoteSelection
        localSelection.assetURL = localURL
        localSelection.headers = [:]

        let resolved = PlaybackSessionController.directPlayRecoverySelection(
            preparedSelection: localSelection,
            gatewayRemoteSelection: remoteSelection
        )

        XCTAssertEqual(resolved.assetURL, remoteURL)
        XCTAssertEqual(resolved.headers["X-Emby-Token"], "secret")
    }

    func testStartupReadinessUsesPreparedLocalGatewaySelectionForDiagnostics() {
        let remoteURL = URL(string: "https://media.example.com/Videos/item/stream.mp4?static=true")!
        let localURL = URL(string: "http://127.0.0.1:59235/media/session.mp4")!
        var remoteSelection = makeWarmedSelection(route: .directPlay(remoteURL))
        remoteSelection.assetURL = remoteURL
        var localSelection = remoteSelection
        localSelection.assetURL = localURL

        let resolved = PlaybackSessionController.startupReadinessLoadedSelection(
            requestedSelection: remoteSelection,
            preparedSelection: localSelection
        )

        XCTAssertEqual(resolved.assetURL, localURL)
    }

    func testGatewayRecoveryKeepsRemoteSelectionWhenAlreadyRemote() {
        let remoteURL = URL(string: "https://media.example.com/Videos/item/stream.mp4?static=true&api_key=secret")!
        var remoteSelection = makeWarmedSelection(route: .directPlay(remoteURL))
        remoteSelection.assetURL = remoteURL
        remoteSelection.headers = ["X-Emby-Token": "secret"]

        let resolved = PlaybackSessionController.directPlayRecoverySelection(
            preparedSelection: remoteSelection,
            gatewayRemoteSelection: nil
        )

        XCTAssertEqual(resolved.assetURL, remoteURL)
        XCTAssertEqual(resolved.headers["X-Emby-Token"], "secret")
    }

    func testGatewayTransportFailureBeforeFirstFrameDisablesGatewayRetry() {
        var localSelection = makeWarmedSelection(
            route: .directPlay(URL(string: "http://127.0.0.1:59235/media/session")!)
        )
        localSelection.assetURL = URL(string: "http://127.0.0.1:59235/media/session")!

        XCTAssertTrue(
            PlaybackSessionController.shouldDisableLocalGatewayForDirectPlayRecovery(
                reason: StartupFailureReason.playerItemFailedTransient.rawValue,
                preparedSelection: localSelection,
                hasMarkedFirstFrame: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldDisableLocalGatewayForDirectPlayRecovery(
                reason: StartupFailureReason.playerItemFailedTransient.rawValue,
                preparedSelection: localSelection,
                hasMarkedFirstFrame: true
            )
        )
    }

    func testGatewayAVFoundationConfigurationFailureBypassesRemoteRetry() {
        var localSelection = makeWarmedSelection(
            route: .directPlay(URL(string: "http://127.0.0.1:59235/media/session")!)
        )
        localSelection.assetURL = URL(string: "http://127.0.0.1:59235/media/session")!

        XCTAssertTrue(
            PlaybackSessionController.shouldBypassSameRouteDirectPlayRecovery(
                reason: StartupFailureReason.playerItemFailedTransient.rawValue,
                preparedSelection: localSelection,
                hasMarkedFirstFrame: false,
                failureDomain: AVFoundationErrorDomain,
                failureCode: AVError.serverIncorrectlyConfigured.rawValue
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldBypassSameRouteDirectPlayRecovery(
                reason: StartupFailureReason.playerItemFailedTransient.rawValue,
                preparedSelection: localSelection,
                hasMarkedFirstFrame: true,
                failureDomain: AVFoundationErrorDomain,
                failureCode: AVError.serverIncorrectlyConfigured.rawValue
            )
        )
    }

    func testSameRouteRecoveryRejectsStaleLocalGatewaySelection() {
        let remoteURL = URL(string: "https://media.example.com/Videos/item/stream.mp4?static=true")!
        let localURL = URL(string: "http://127.0.0.1:59235/media/session")!
        var remoteSelection = makeWarmedSelection(route: .directPlay(remoteURL))
        remoteSelection.assetURL = remoteURL
        var localSelection = remoteSelection
        localSelection.assetURL = localURL

        XCTAssertFalse(
            PlaybackSessionController.canAttemptSameRouteDirectPlayRecovery(
                preparedSelection: localSelection,
                gatewayRemoteSelection: nil
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.canAttemptSameRouteDirectPlayRecovery(
                preparedSelection: localSelection,
                gatewayRemoteSelection: remoteSelection
            )
        )
    }

    func testAppleNativeRecoveryAllowsProfileFallbackButSampleBufferBlocks() {
        XCTAssertFalse(
            PlaybackSessionController.shouldBlockLegacyCoordinatorRecovery(
                isNativePlayerActive: true,
                nativeSurface: .appleNative
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldBlockLegacyCoordinatorRecovery(
                isNativePlayerActive: true,
                nativeSurface: .sampleBuffer
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldBlockLegacyCoordinatorRecovery(
                isNativePlayerActive: false,
                nativeSurface: .sampleBuffer
            )
        )
    }

    func testAppleNativeFallbackAllowsCoordinatorAfterMeasuredFailure() {
        XCTAssertTrue(
            PlaybackSessionController.shouldAllowAppleNativeCoordinatorFallback(
                reason: StartupFailureReason.playerItemFailedTransient.rawValue,
                isNativePlayerActive: false,
                nativeSurface: .appleNative
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldAllowAppleNativeCoordinatorFallback(
                reason: StartupFailureReason.playerItemFailedTransient.rawValue,
                isNativePlayerActive: true,
                nativeSurface: .sampleBuffer
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldAllowAppleNativeCoordinatorFallback(
                reason: StartupFailureReason.directPlayPostStartStall.rawValue,
                isNativePlayerActive: false,
                nativeSurface: .appleNative
            )
        )
    }

    func testBeginningStartPositionIgnoresServerAndLocalResumeProgress() {
        let item = MediaItem(
            id: "movie-start",
            name: "Movie",
            mediaType: .movie,
            runtimeTicks: Int64(90 * 60 * 10_000_000),
            playbackPositionTicks: Int64(26 * 60 * 10_000_000)
        )
        let localProgress = PlaybackProgress(
            itemID: "movie-start",
            positionTicks: Int64(31 * 60 * 10_000_000),
            totalTicks: Int64(90 * 60 * 10_000_000),
            updatedAt: Date()
        )

        XCTAssertNil(
            PlaybackSessionController.resolvedResumeSeconds(
                for: item,
                localProgress: localProgress,
                startPosition: .beginning
            )
        )
        XCTAssertEqual(
            PlaybackSessionController.resolvedResumeSeconds(
                for: item,
                localProgress: localProgress,
                startPosition: .resumeIfAvailable
            ),
            31 * 60
        )
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

    func testTvOSHighBitrateDirectPlayDoesNotBlockAutoplayOnGuardedStartupTimeout() {
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

        XCTAssertFalse(shouldBlock)
    }

    func testIPhoneHighBitrateResumeDirectPlayBlocksAutoplayOnGuardedStartupTimeout() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let shouldBlock = PlaybackSessionController.shouldBlockAutoplayAfterUnsafeStartup(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            source: source,
            runtimeSeconds: 7_200,
            resumeSeconds: 1_225.3,
            isTVOS: false
        )

        XCTAssertTrue(shouldBlock)
    }

    func testUnsafeDirectPlayStartupBlockSuppressesLaterPlayRequests() {
        let directRoute = PlaybackRoute.directPlay(URL(string: "https://example.com/Videos/item-premium/stream.mp4?static=true")!)
        let transcodeRoute = PlaybackRoute.transcode(URL(string: "https://example.com/Videos/item-premium/master.m3u8")!)

        XCTAssertTrue(
            PlaybackSessionController.shouldIgnorePlayRequestAfterUnsafeDirectPlayStartup(
                startupPlaybackBlocked: true,
                route: directRoute
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldIgnorePlayRequestAfterUnsafeDirectPlayStartup(
                startupPlaybackBlocked: true,
                route: nil
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldIgnorePlayRequestAfterUnsafeDirectPlayStartup(
                startupPlaybackBlocked: false,
                route: directRoute
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldIgnorePlayRequestAfterUnsafeDirectPlayStartup(
                startupPlaybackBlocked: true,
                route: transcodeRoute
            )
        )
    }

    func testIPhoneStrictDirectPlayStartupUsesPrerollDuringReadinessGate() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 20,
            preferredBufferDuration: 30,
            timeout: 45,
            pollInterval: 0.15,
            reason: "ios_hdr_dv_resume_directplay_ready",
            allowsTimeoutStart: false
        )

        XCTAssertTrue(
            PlaybackSessionController.shouldPrerollDuringStartupReadinessGate(
                route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream.mp4?static=true&MediaSourceId=premium-source")!),
                source: source,
                requirement: requirement,
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldPrerollDuringStartupReadinessGate(
                route: .transcode(URL(string: "https://example.com/Videos/item-premium/master.m3u8")!),
                source: source,
                requirement: requirement,
                isTVOS: false
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldPrerollDuringStartupReadinessGate(
                route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream.mp4?static=true&MediaSourceId=premium-source")!),
                source: source,
                requirement: requirement,
                isTVOS: true
            )
        )
    }

    func testIPhoneHighRiskProgressiveDirectPlayDoesNotPreemptToStableHLSWithoutMeasurement() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            videoWidth: 3_840,
            videoHeight: 1_608
        )

        let shouldPreempt = PlaybackSessionController.shouldPreemptivelyUseStableHLSForHighRiskDirectPlay(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream.mp4?static=true&MediaSourceId=premium-source")!),
            source: source,
            playbackPolicy: .auto,
            allowSDRFallback: true,
            usesDirectRemuxOnly: false,
            maxStreamingBitrate: 120_000_000,
            isTVOS: false
        )

        XCTAssertFalse(shouldPreempt)
    }

    func testIPhoneHighRiskStrictQualityDirectPlayKeepsNativePath() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            videoWidth: 3_840,
            videoHeight: 1_608
        )

        let shouldPreempt = PlaybackSessionController.shouldPreemptivelyUseStableHLSForHighRiskDirectPlay(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream.mp4?static=true&MediaSourceId=premium-source")!),
            source: source,
            playbackPolicy: .auto,
            allowSDRFallback: false,
            usesDirectRemuxOnly: false,
            maxStreamingBitrate: 120_000_000,
            isTVOS: false
        )

        XCTAssertFalse(shouldPreempt)
    }

    func testIPhoneHighRiskDirectRemuxOnlyKeepsNativePath() {
        let source = MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            videoWidth: 3_840,
            videoHeight: 1_608
        )

        let shouldPreempt = PlaybackSessionController.shouldPreemptivelyUseStableHLSForHighRiskDirectPlay(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream.mp4?static=true&MediaSourceId=premium-source")!),
            source: source,
            playbackPolicy: .auto,
            allowSDRFallback: true,
            usesDirectRemuxOnly: true,
            maxStreamingBitrate: 120_000_000,
            isTVOS: false
        )

        XCTAssertFalse(shouldPreempt)
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

        let shouldPreempt = PlaybackSessionController.shouldPreemptivelyUseStableHLSForHighRiskDirectPlay(
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

        let shouldPreempt = PlaybackSessionController.shouldPreemptivelyUseStableHLSForHighRiskDirectPlay(
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

        let shouldPreempt = PlaybackSessionController.shouldPreemptivelyUseStableHLSForHighRiskDirectPlay(
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

    func testTvOSHighBitrateDirectPlayWithNetworkHeadroomUsesGuardedStartupPolicy() {
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

        XCTAssertEqual(policy.forwardBufferDuration, 4)
        XCTAssertTrue(policy.waitsToMinimizeStalling)
        XCTAssertEqual(policy.reason, "tvos_guarded_directplay_startup")
    }

    func testTvOSOrdinaryDirectPlayWithNetworkHeadroomUsesFastStartupPolicy() {
        let source = MediaSource(
            id: "ordinary-source",
            itemID: "item-ordinary",
            name: "Ordinary stream",
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            bitrate: 8_000_000,
            videoBitDepth: 8,
            videoRangeType: "SDR",
            supportsDirectPlay: true,
            supportsDirectStream: true
        )

        let policy = PlaybackSessionController.directPlayStabilityPolicy(
            route: .directPlay(URL(string: "https://example.com/Videos/item-ordinary/stream?static=true&MediaSourceId=ordinary-source")!),
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

    func testStartupDirectPlayFailuresUseSameRouteExceptPostStartStalls() {
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
        XCTAssertFalse(
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

    func testTvOSHighBitrateDirectPlayPrestartGuardKeepsDirectPlayWithoutMeasuredEvidence() {
        let reason = PlaybackSessionController.directPlayPrestartRecoveryReason(
            route: .directPlay(URL(string: "https://example.com/Videos/item-premium/stream?static=true&MediaSourceId=premium-source")!),
            sourceBitrate: 21_868_794,
            preheatResult: nil,
            isTVOS: true
        )

        XCTAssertNil(reason)
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

    func testDirectPlayPendingResumeDelaysFirstFrameUntilResumePosition() {
        let route = PlaybackRoute.directPlay(URL(string: "https://example.com/Videos/item/stream?static=true")!)

        XCTAssertTrue(PlaybackSessionController.shouldDelayFirstFrameUntilResumePosition(
            route: route,
            pendingResumeSeconds: 1_546.112,
            currentTime: 0,
            transcodeStartOffset: 0
        ))
        XCTAssertFalse(PlaybackSessionController.shouldDelayFirstFrameUntilResumePosition(
            route: route,
            pendingResumeSeconds: 1_546.112,
            currentTime: 1_546.2,
            transcodeStartOffset: 0
        ))
        XCTAssertFalse(PlaybackSessionController.shouldDelayFirstFrameUntilResumePosition(
            route: .transcode(URL(string: "https://example.com/Videos/item/master.m3u8?StartTimeTicks=15461120000")!),
            pendingResumeSeconds: 1_546.112,
            currentTime: 0,
            transcodeStartOffset: 1_546.112
        ))
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

    private func premiumDirectPlaySource() -> MediaSource {
        MediaSource(
            id: "premium-source",
            itemID: "item-premium",
            name: "Premium stream",
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 21_868_794,
            videoBitDepth: 10,
            videoRangeType: "DOVIWithHDR10",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            audioTracks: [
                MediaTrack(
                    id: "track-2",
                    title: "French - Dolby Digital+ - 5.1 - Default",
                    language: "fra",
                    codec: "eac3",
                    isDefault: true,
                    index: 2
                )
            ]
        )
    }

    private func makeSelection(
        source: MediaSource,
        route: PlaybackRoute,
        assetURL: URL
    ) -> PlaybackAssetSelection {
        PlaybackAssetSelection(
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
