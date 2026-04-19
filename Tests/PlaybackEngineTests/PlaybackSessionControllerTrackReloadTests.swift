import AVFoundation
import CoreGraphics
@testable import PlaybackEngine
@testable import ReelFinUI
import Shared
import XCTest

@MainActor
final class PlaybackSessionControllerTrackReloadTests: XCTestCase {
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

    func testPresentationSizeAloneDoesNotCountAsRenderedFrameWhenOutputIsAttached() {
        XCTAssertFalse(
            PlaybackSessionController.hasRenderableVideoFrame(
                copiedPixelBuffer: false,
                presentationSize: CGSize(width: 3840, height: 1608),
                videoOutputAttached: true
            )
        )
    }

    func testCopiedPixelBufferCountsAsRenderedFrame() {
        XCTAssertTrue(
            PlaybackSessionController.hasRenderableVideoFrame(
                copiedPixelBuffer: true,
                presentationSize: CGSize(width: 3840, height: 1608),
                videoOutputAttached: true
            )
        )
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

    func testTvOSDirectPlayDoesNotUseIPhoneVideoPrerollGate() {
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

    func testPremiumProgressiveDirectPlayUsesStallResistantBufferingOnTvOS() {
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

        XCTAssertEqual(policy.forwardBufferDuration, 12)
        XCTAssertTrue(policy.waitsToMinimizeStalling)
        XCTAssertEqual(policy.reason, "premium_direct_play_stability")
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

    func testRepeatedPremiumDirectPlayStallsTriggerRecovery() {
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

    func testLateFirstFrameStallsStillTriggerRecovery() {
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

    func testSingleDirectPlayStallDoesNotTriggerRecovery() {
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
            elapsedSecondsSinceFirstFrame: 12
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
