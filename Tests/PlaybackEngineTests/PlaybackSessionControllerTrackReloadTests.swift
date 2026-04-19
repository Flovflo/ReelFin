import AVFoundation
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

    func testPremiumProgressiveDirectPlayUsesStallResistantBuffering() {
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
            defaultWaitsToMinimizeStalling: false
        )

        XCTAssertEqual(policy.forwardBufferDuration, 12)
        XCTAssertTrue(policy.waitsToMinimizeStalling)
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
            defaultWaitsToMinimizeStalling: false
        )

        XCTAssertEqual(policy.forwardBufferDuration, 2)
        XCTAssertFalse(policy.waitsToMinimizeStalling)
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
}
