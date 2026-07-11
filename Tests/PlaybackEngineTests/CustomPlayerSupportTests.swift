import AVFoundation
import Foundation
import Shared
import XCTest
@testable import PlaybackEngine

/// Pure support logic of the custom player: MIME resolution (the tvOS no-first-frame root cause),
/// external subtitle track building, and the subtitle cue pipeline.
final class CustomPlayerSupportTests: XCTestCase {
    func testMKVHEVCAndH264RequireNativeDemuxInsteadOfJellyfinFMP4() {
        XCTAssertTrue(
            JellyfinOriginalSourceResolver.requiresNativeOriginalPlayback(
                for: makeSource(container: "mkv", filePath: "/media/episode.mkv", videoCodec: "hevc")
            )
        )
        XCTAssertTrue(
            JellyfinOriginalSourceResolver.requiresNativeOriginalPlayback(
                for: makeSource(container: "matroska", filePath: nil, videoCodec: "h264")
            )
        )
    }

    func testAppleNativeMP4AndUnsupportedMKVCodecStayOutOfNativeDemuxHandoff() {
        XCTAssertFalse(
            JellyfinOriginalSourceResolver.requiresNativeOriginalPlayback(
                for: makeSource(container: "mp4", filePath: "/media/movie.mp4", videoCodec: "hevc")
            )
        )
        XCTAssertFalse(
            JellyfinOriginalSourceResolver.requiresNativeOriginalPlayback(
                for: makeSource(container: "mkv", filePath: "/media/movie.mkv", videoCodec: "av1")
            )
        )
    }

    func testAdaptiveVideoCopyUsesOriginalQualityPhase() {
        XCTAssertEqual(
            CustomAdaptivePlaybackPolicy.phase(isStarving: false, preservesOriginalVideo: true),
            .playing
        )
        XCTAssertEqual(
            CustomAdaptivePlaybackPolicy.phase(isStarving: false, preservesOriginalVideo: false),
            .degradedSDR
        )
        XCTAssertEqual(
            CustomAdaptivePlaybackPolicy.phase(isStarving: true, preservesOriginalVideo: true),
            .buffering
        )
    }

    // MARK: - Local-cache steady-state transport

    @MainActor
    func testLocalCacheTransportDoesNotForceHugeCoreMediaReadAhead() {
        let player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = true
        let item = AVPlayerItem(asset: AVMutableComposition())
        item.preferredForwardBufferDuration = 30

        CustomLocalCachePlaybackPolicy.configure(player: player, item: item)

        XCTAssertEqual(item.preferredForwardBufferDuration, 0,
            "the disk reservoir owns read-ahead; forcing 30s makes CoreMedia request ~130MB 4K ranges and exhaust CRABS")
        XCTAssertFalse(player.automaticallyWaitsToMinimizeStalling,
            "localhost cache misses must surface immediately instead of parking forever in AVPlayerWaitingToMinimizeStallsReason")
    }

    func testDeepCachedStallEscalatesFromImmediatePlayToWarmItemRebuild() {
        XCTAssertEqual(
            CustomLocalCachePlaybackPolicy.recoveryAction(
                isWaiting: true,
                observedPlaybackStall: false,
                reservoirSeconds: 120,
                stagnantSeconds: 2.1,
                alreadyForcedImmediatePlayback: false
            ),
            .forceImmediatePlayback
        )
        XCTAssertEqual(
            CustomLocalCachePlaybackPolicy.recoveryAction(
                isWaiting: true,
                observedPlaybackStall: false,
                reservoirSeconds: 120,
                stagnantSeconds: 6.1,
                alreadyForcedImmediatePlayback: true
            ),
            .rebuildWarmItem
        )
        XCTAssertEqual(
            CustomLocalCachePlaybackPolicy.recoveryAction(
                isWaiting: true,
                observedPlaybackStall: false,
                reservoirSeconds: 0,
                stagnantSeconds: 30,
                alreadyForcedImmediatePlayback: true
            ),
            .waitForBytes,
            "an actual empty cache is a network/data stall, not a poisoned local AVPlayer item"
        )
    }

    func testExplicitDeepCachedStallForcesImmediatePlaybackWithoutVisibleDelay() {
        XCTAssertEqual(
            CustomLocalCachePlaybackPolicy.recoveryAction(
                isWaiting: false,
                observedPlaybackStall: true,
                reservoirSeconds: 503,
                stagnantSeconds: 0,
                alreadyForcedImmediatePlayback: false
            ),
            .forceImmediatePlayback,
            "PlaybackStalled with a deep localhost reservoir is not a network wait; resume it on the notification tick"
        )
    }

    func testResidualClockCoastCannotClearPausedPlaybackStall() {
        XCTAssertFalse(
            CustomLocalCachePlaybackPolicy.hasRecoveredFromObservedStall(
                positionAdvanced: true,
                playbackRate: 0
            ),
            "the device advanced a fraction after PlaybackStalled, then stayed permanently at rate 0"
        )
        XCTAssertTrue(
            CustomLocalCachePlaybackPolicy.hasRecoveredFromObservedStall(
                positionAdvanced: true,
                playbackRate: 1
            )
        )
    }

    func testNoStallWaitPausedStateIsRecoverableOnlyAfterObservedPlaybackStall() {
        XCTAssertTrue(
            CustomLocalCachePlaybackPolicy.transportNeedsRecovery(
                isWaiting: false,
                observedPlaybackStall: true
            ),
            "CoreMedia NoStallWait changes to .paused after PlaybackStalled; that paused stall must enter recovery"
        )
        XCTAssertFalse(
            CustomLocalCachePlaybackPolicy.transportNeedsRecovery(
                isWaiting: false,
                observedPlaybackStall: false
            ),
            "a normal user pause must never be auto-resumed"
        )
    }

    // MARK: - Audio output recovery

    func testPhysicalIOSPlaybackAudioConfigurationNeverUsesPlayAndRecordOnlyAirPlayOption() {
        let configuration = PlaybackAudioSessionPolicy.configuration(isSimulator: false)

        XCTAssertEqual(configuration.category, .playback)
        XCTAssertEqual(configuration.mode, .moviePlayback)
        XCTAssertFalse(
            configuration.options.contains(.allowAirPlay),
            "the iOS SDK only permits allowAirPlay with playAndRecord; using it with playback returns OSStatus -50"
        )
    }

    func testNewAudioDeviceRouteDoesNotReenterSessionActivation() {
        XCTAssertFalse(
            CustomPlayerAudioRecoveryPolicy.shouldRecoverRouteChange(.newDeviceAvailable),
            "activating the playback session can publish this route event; reacting would activate a second time while playback starts"
        )
    }

    func testAudioRouteLossReactivatesSessionAndPreservesPlayingIntent() {
        XCTAssertTrue(
            CustomPlayerAudioRecoveryPolicy.shouldRecoverRouteChange(.oldDeviceUnavailable),
            "a genuine output removal still needs session recovery"
        )
        XCTAssertEqual(
            CustomPlayerAudioRecoveryPolicy.decision(
                for: .routeChanged,
                wasPlaying: true
            ),
            .init(reactivateSession: true, resumePlayback: true)
        )
    }

    func testAudioRouteChangeWhilePausedNeverStartsPlayback() {
        XCTAssertEqual(
            CustomPlayerAudioRecoveryPolicy.decision(
                for: .routeChanged,
                wasPlaying: false
            ),
            .init(reactivateSession: true, resumePlayback: false)
        )
    }

    func testInterruptionEndOnlyResumesWhenSystemAndUserIntentAllowIt() {
        XCTAssertEqual(
            CustomPlayerAudioRecoveryPolicy.decision(
                for: .interruptionEnded(systemShouldResume: true),
                wasPlaying: true
            ),
            .init(reactivateSession: true, resumePlayback: true)
        )
        XCTAssertEqual(
            CustomPlayerAudioRecoveryPolicy.decision(
                for: .interruptionEnded(systemShouldResume: false),
                wasPlaying: true
            ),
            .init(reactivateSession: true, resumePlayback: false)
        )
        XCTAssertEqual(
            CustomPlayerAudioRecoveryPolicy.decision(
                for: .interruptionEnded(systemShouldResume: true),
                wasPlaying: false
            ),
            .init(reactivateSession: true, resumePlayback: false)
        )
    }

    // MARK: - First-frame proof

    func testIOSRejectsTimelineOnlyAsVisibleFirstFrameProof() {
        XCTAssertFalse(
            CustomPlayerFirstFrameProofPolicy.acceptsTimelineProgress(
                isTVOS: false,
                isExternalPlaybackActive: false,
                itemReady: true,
                previousSeconds: 12,
                currentSeconds: 13
            ),
            "audio/timeline can advance while the iOS AVKit surface is still black or detached"
        )
    }

    func testTVOSLocalPlaybackKeepsLaunchCoverUntilAVKitSurfaceIsVisible() {
        XCTAssertFalse(
            CustomPlayerFirstFrameProofPolicy.acceptsTimelineProgress(
                isTVOS: true,
                isExternalPlaybackActive: false,
                itemReady: true,
                previousSeconds: 12,
                currentSeconds: 13
            )
        )
        XCTAssertFalse(
            CustomPlayerFirstFrameProofPolicy.acceptsLocalPixelProbe(
                isTVOS: true,
                videoFramesObserved: true
            ),
            "a decoded probe frame can arrive before AVPlayerViewController presents it; only isReadyForDisplay may remove the cover"
        )
    }

    func testTVOSAirPlayAcceptsReadyAdvancingTimeline() {
        XCTAssertTrue(
            CustomPlayerFirstFrameProofPolicy.acceptsTimelineProgress(
                isTVOS: true,
                isExternalPlaybackActive: true,
                itemReady: true,
                previousSeconds: 12,
                currentSeconds: 12.25
            )
        )
        XCTAssertFalse(
            CustomPlayerFirstFrameProofPolicy.acceptsTimelineProgress(
                isTVOS: true,
                isExternalPlaybackActive: true,
                itemReady: false,
                previousSeconds: 12,
                currentSeconds: 13
            )
        )
    }

    // MARK: - MIME (tvOS device regression 2026-07-02)

    /// ffmpeg labels the WHOLE QuickTime family — including real .mp4 files — with the composite
    /// "mov,mp4,m4a,3gp,3g2,mj2" (live-probed: an actual '.mp4' carries exactly that string). The
    /// composite therefore resolves to video/mp4; only a file extension can say "QuickTime".
    func testOverrideMIMETypeCompositeContainerResolvesToMp4() {
        let source = makeSource(container: "mov,mp4,m4a,3gp,3g2,mj2", filePath: nil)
        let mime = JellyfinOriginalSourceResolver.overrideMIMEType(
            for: URL(string: "https://server/Videos/x/stream")!, source: source)
        XCTAssertEqual(mime, "video/mp4")
    }

    func testOverrideMIMETypeUsesFilePathExtensionFirst() {
        let mkv = makeSource(container: "mov,mp4", filePath: "/media/movie.mkv")
        XCTAssertEqual(
            JellyfinOriginalSourceResolver.overrideMIMEType(
                for: URL(string: "https://server/Videos/x/stream")!, source: mkv),
            "video/x-matroska")
        let mov = makeSource(container: "mov,mp4,m4a,3gp,3g2,mj2", filePath: "/media/movie.mov")
        XCTAssertEqual(
            JellyfinOriginalSourceResolver.overrideMIMEType(
                for: URL(string: "https://server/Videos/x/stream")!, source: mov),
            "video/quicktime")
        let mp4 = makeSource(container: "mov,mp4,m4a,3gp,3g2,mj2", filePath: "/media/movie.mp4")
        XCTAssertEqual(
            JellyfinOriginalSourceResolver.overrideMIMEType(
                for: URL(string: "https://server/Videos/x/stream")!, source: mp4),
            "video/mp4")
    }

    func testOverrideMIMETypePlainMp4StaysMp4() {
        let source = makeSource(container: "mp4", filePath: nil)
        let mime = JellyfinOriginalSourceResolver.overrideMIMEType(
            for: URL(string: "https://server/Videos/x/stream")!, source: source)
        XCTAssertEqual(mime, "video/mp4")
    }

    // MARK: - External subtitle tracks

    func testExternalSubtitleTracksBuildDeliveryURLsForTextFormatsOnly() {
        var source = makeSource(container: "mp4", filePath: nil)
        source.subtitleTracks = [
            MediaTrack(id: "s1", title: "Français", language: "fr", codec: "srt", isDefault: true, index: 3),
            MediaTrack(id: "s2", title: "PGS", language: "en", codec: "pgssub", isDefault: false, index: 4),
            MediaTrack(id: "s3", title: "", language: "en", codec: "subrip", isDefault: false, index: 5)
        ]
        let assetURL = URL(string: "https://server.example/Videos/item-1/stream?static=true&api_key=tok123")!
        let tracks = JellyfinOriginalSourceResolver.externalSubtitleTracks(for: source, assetURL: assetURL)

        XCTAssertEqual(tracks.count, 2, "image-based formats (PGS) cannot be text-rendered")
        XCTAssertEqual(tracks[0].label, "Français")
        XCTAssertEqual(tracks[0].url.path, "/Videos/\(source.itemID)/\(source.id)/Subtitles/3/0/Stream.srt")
        XCTAssertTrue(tracks[0].url.query?.contains("api_key=tok123") ?? false)
        XCTAssertEqual(tracks[1].label, "en", "untitled tracks fall back to their language")
    }

    func testPreferredStableTwinKeepsSiblingSubtitleDeliverySource() throws {
        var subtitleOwner = makeSource(container: "mkv", filePath: "/media/episode.mkv")
        subtitleOwner.id = "subtitle-owner"
        subtitleOwner.subtitleTracks = [
            MediaTrack(
                id: "s1",
                title: "Français",
                language: "fr",
                codec: "subrip",
                isDefault: false,
                index: 7
            )
        ]
        var stable = makeSource(container: "mp4", filePath: "/media/episode.mp4")
        stable.id = "stable-video"

        let enriched = try XCTUnwrap(
            PlaybackCoordinator.preferringContainers(
                [subtitleOwner, stable],
                ["mp4"],
                itemID: stable.itemID
            ).first
        )
        let tracks = JellyfinOriginalSourceResolver.externalSubtitleTracks(
            for: enriched,
            assetURL: URL(string: "https://server.example/Videos/item/stream?api_key=redacted")!
        )

        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(
            tracks.first?.url.path,
            "/Videos/\(stable.itemID)/subtitle-owner/Subtitles/7/0/Stream.srt"
        )
    }

    // MARK: - Subtitle cue pipeline

    @MainActor
    func testSubtitleParsingAndCueLookup() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,500
        <i>Bonjour</i> le monde

        2
        00:00:10,000 --> 00:00:12,000
        {\\an8}Deuxième réplique
        ligne deux
        """
        let cues = try XCTUnwrap(SubtitleOverlayModel.parse(text: srt))
        XCTAssertEqual(cues.count, 2)

        let model = makeModel(with: srt)
        model.updateTime(2.0)
        XCTAssertEqual(model.currentCue, "Bonjour le monde", "markup must be stripped")
        model.updateTime(5.0)
        XCTAssertNil(model.currentCue, "gap between cues shows nothing")
        model.updateTime(11.0)
        XCTAssertEqual(model.currentCue, "Deuxième réplique\nligne deux")
        // Backwards seek restarts the cursor.
        model.updateTime(2.0)
        XCTAssertEqual(model.currentCue, "Bonjour le monde")
    }

    func testVTTTimestampParsing() {
        XCTAssertEqual(SubtitleOverlayModel.seconds(fromVTTTimestamp: "01:02:03.500"), 3_723.5)
        XCTAssertEqual(SubtitleOverlayModel.seconds(fromVTTTimestamp: "02:03.250"), 123.25)
        XCTAssertNil(SubtitleOverlayModel.seconds(fromVTTTimestamp: "garbage"))
    }

    // MARK: - Helpers

    @MainActor
    private func makeModel(with srt: String) -> SubtitleOverlayModel {
        let model = SubtitleOverlayModel()
        model.debugInstall(cuesFrom: srt)
        return model
    }

    private func makeSource(
        container: String?,
        filePath: String?,
        videoCodec: String? = nil
    ) -> MediaSource {
        MediaSource(
            id: "source-1",
            itemID: "item-1",
            name: "Fixture",
            filePath: filePath,
            container: container,
            videoCodec: videoCodec,
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
    }
}
