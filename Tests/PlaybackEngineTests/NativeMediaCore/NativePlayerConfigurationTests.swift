@testable import ReelFinUI
import CoreMedia
import NativeMediaCore
import Shared
import XCTest

@MainActor
final class NativePlayerConfigurationTests: XCTestCase {
    func testMatroskaProgressStartTimeUpdatesDoNotRestartPlayback() {
        let controller = NativeMatroskaSampleBufferPlayerController()
        _ = controller.view
        let url = URL(fileURLWithPath: "/tmp/native-\(UUID().uuidString).mkv")
        let headers = ["Authorization": "MediaBrowser Token=redacted"]

        controller.configure(
            url: url,
            headers: headers,
            container: .matroska,
            startTimeSeconds: 21.248,
            seekRequest: nil,
            selectedAudioTrackID: nil,
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )
        let generation = controller.playbackGeneration
        let pauseApplications = controller.pauseStateApplicationCount

        controller.configure(
            url: url,
            headers: headers,
            container: .matroska,
            startTimeSeconds: 42.0,
            seekRequest: nil,
            selectedAudioTrackID: nil,
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )

        XCTAssertEqual(controller.playbackGeneration, generation)
        XCTAssertEqual(controller.pauseStateApplicationCount, pauseApplications)
        controller.stopForDismantle()
    }

    func testMatroskaForwardSeekKeepsCurrentReaderAndCoalescesRequest() {
        let controller = NativeMatroskaSampleBufferPlayerController()
        _ = controller.view
        let url = URL(fileURLWithPath: "/tmp/native-\(UUID().uuidString).mkv")

        controller.configure(
            url: url,
            headers: [:],
            container: .matroska,
            startTimeSeconds: 0,
            seekRequest: nil,
            selectedAudioTrackID: nil,
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )
        let generation = controller.playbackGeneration
        let request = NativePlayerSeekRequest(id: 1, targetSeconds: 42)

        controller.configure(
            url: url,
            headers: [:],
            container: .matroska,
            startTimeSeconds: 0,
            seekRequest: request,
            selectedAudioTrackID: nil,
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )
        XCTAssertEqual(controller.playbackGeneration, generation)
        XCTAssertEqual(controller.forwardSeekRequestCount, 1)

        controller.configure(
            url: url,
            headers: [:],
            container: .matroska,
            startTimeSeconds: 0,
            seekRequest: request,
            selectedAudioTrackID: nil,
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )
        XCTAssertEqual(controller.playbackGeneration, generation)
        XCTAssertEqual(controller.forwardSeekRequestCount, 1)
        controller.stopForDismantle()
    }

    func testMatroskaForwardSeekWaitsForVideoKeyframeBeforeDecode() {
        var state = NativeMatroskaForwardSeekState(targetSeconds: 100)

        XCTAssertTrue(state.shouldSkip(
            makePacket(trackID: 1, seconds: 100.0, keyframe: false),
            videoTrackID: 1,
            audioTrackID: nil,
            subtitleTrackID: nil
        ))
        XCTAssertTrue(state.shouldSkip(
            makePacket(trackID: 1, seconds: 96.0, keyframe: true),
            videoTrackID: 1,
            audioTrackID: nil,
            subtitleTrackID: nil
        ))
        XCTAssertFalse(state.shouldSkip(
            makePacket(trackID: 1, seconds: 98.0, keyframe: true),
            videoTrackID: 1,
            audioTrackID: nil,
            subtitleTrackID: nil
        ))
        XCTAssertFalse(state.shouldSkip(
            makePacket(trackID: 1, seconds: 100.1, keyframe: false),
            videoTrackID: 1,
            audioTrackID: nil,
            subtitleTrackID: nil
        ))
    }

    func testMatroskaForwardSeekSkipsAudioUntilTarget() {
        var state = NativeMatroskaForwardSeekState(targetSeconds: 100)

        XCTAssertTrue(state.shouldSkip(
            makePacket(trackID: 2, seconds: 99.9, keyframe: true),
            videoTrackID: 1,
            audioTrackID: 2,
            subtitleTrackID: nil
        ))
        XCTAssertFalse(state.shouldSkip(
            makePacket(trackID: 2, seconds: 99.99, keyframe: true),
            videoTrackID: 1,
            audioTrackID: 2,
            subtitleTrackID: nil
        ))
    }

    func testMatroskaTrackSelectionRestartsReaderAtCurrentSurface() {
        let controller = NativeMatroskaSampleBufferPlayerController()
        _ = controller.view
        let url = URL(fileURLWithPath: "/tmp/native-\(UUID().uuidString).mkv")

        controller.configure(
            url: url,
            headers: [:],
            container: .matroska,
            startTimeSeconds: 0,
            seekRequest: nil,
            selectedAudioTrackID: "1",
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )
        let generation = controller.playbackGeneration

        controller.configure(
            url: url,
            headers: [:],
            container: .matroska,
            startTimeSeconds: 0,
            seekRequest: nil,
            selectedAudioTrackID: "2",
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )

        XCTAssertEqual(controller.playbackGeneration, generation + 1)
        controller.stopForDismantle()
    }

    func testMP4ProgressStartTimeUpdatesDoNotRestartPlayback() {
        let controller = NativeMP4SampleBufferPlayerController()
        _ = controller.view
        let url = URL(fileURLWithPath: "/tmp/native-\(UUID().uuidString).mp4")

        controller.configure(
            url: url,
            startTimeSeconds: 12.0,
            seekRequest: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )
        let generation = controller.playbackGeneration
        let pauseApplications = controller.pauseStateApplicationCount

        controller.configure(
            url: url,
            startTimeSeconds: 20.0,
            seekRequest: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )

        XCTAssertEqual(controller.playbackGeneration, generation)
        XCTAssertEqual(controller.pauseStateApplicationCount, pauseApplications)
        controller.stopForDismantle()
    }

    func testPauseStateGateAppliesOnlyWhenStateChanges() {
        var gate = NativePauseStateGate()

        XCTAssertTrue(gate.shouldApply(false))
        XCTAssertFalse(gate.shouldApply(false))
        XCTAssertTrue(gate.shouldApply(true))
        XCTAssertFalse(gate.shouldApply(true))

        gate.reset()
        XCTAssertTrue(gate.shouldApply(true))
    }

    func testMatroskaDiagnosticsDoNotKeepFailedAudioAsStartupRequirement() {
        var metrics = NativeMatroskaSampleBufferMetrics()

        metrics.audioDecoderBackend = "AppleAudioToolbox"
        XCTAssertTrue(metrics.requiresAudioForBuffering)

        metrics.audioDecoderBackend = "failed"
        XCTAssertFalse(metrics.requiresAudioForBuffering)

        metrics.audioDecoderBackend = "degraded"
        XCTAssertFalse(metrics.requiresAudioForBuffering)

        metrics.audioDecoderBackend = "none"
        XCTAssertFalse(metrics.requiresAudioForBuffering)
    }

    func testNativePlayerChromePresentationUsesSeriesTitleForEpisodes() {
        let item = MediaItem(
            id: "episode",
            name: "Deuce",
            mediaType: .episode,
            runtimeTicks: 3_064_000_000,
            seriesName: "Your Friends & Neighbors",
            indexNumber: 2,
            parentIndexNumber: 1
        )

        let presentation = NativePlayerChromePresentation(
            item: item,
            playbackTime: 14 * 60 + 24,
            durationSeconds: 51 * 60 + 7
        )

        XCTAssertEqual(presentation.eyebrow, "S1, E2 · Deuce")
        XCTAssertEqual(presentation.title, "Your Friends & Neighbors")
        XCTAssertEqual(presentation.currentTimeText, "14:24")
        XCTAssertEqual(presentation.remainingTimeText, "-36:43")
    }

    func testNativePlayerChromePresentationFallsBackToMovieTitleAndYear() {
        let item = MediaItem(id: "movie", name: "Ready Player One", mediaType: .movie, year: 2018)

        let presentation = NativePlayerChromePresentation(
            item: item,
            playbackTime: 0,
            durationSeconds: nil
        )

        XCTAssertEqual(presentation.eyebrow, "2018")
        XCTAssertEqual(presentation.title, "Ready Player One")
        XCTAssertEqual(presentation.currentTimeText, "0:00")
        XCTAssertEqual(presentation.remainingTimeText, "--:--")
        XCTAssertEqual(presentation.progress, 0)
    }

    func testNativePlayerChromeVisibilityPolicyKeepsBlockingStatesVisible() {
        XCTAssertTrue(NativePlayerChromeVisibilityPolicy.shouldShowChrome(
            isUserActive: false,
            isPaused: true,
            isBuffering: false,
            showsDiagnostics: false,
            hasError: false
        ))
        XCTAssertTrue(NativePlayerChromeVisibilityPolicy.shouldShowChrome(
            isUserActive: false,
            isPaused: false,
            isBuffering: true,
            showsDiagnostics: false,
            hasError: false
        ))
        XCTAssertTrue(NativePlayerChromeVisibilityPolicy.shouldShowChrome(
            isUserActive: false,
            isPaused: false,
            isBuffering: false,
            showsDiagnostics: true,
            hasError: false
        ))
        XCTAssertTrue(NativePlayerChromeVisibilityPolicy.shouldShowChrome(
            isUserActive: false,
            isPaused: false,
            isBuffering: false,
            showsDiagnostics: false,
            hasError: true
        ))
    }

    func testNativePlayerChromeVisibilityPolicyAutoHidesOnlyDuringCleanPlayback() {
        XCTAssertTrue(NativePlayerChromeVisibilityPolicy.shouldAutoHide(
            isPaused: false,
            isBuffering: false,
            showsDiagnostics: false,
            hasError: false
        ))
        XCTAssertFalse(NativePlayerChromeVisibilityPolicy.shouldAutoHide(
            isPaused: true,
            isBuffering: false,
            showsDiagnostics: false,
            hasError: false
        ))
        XCTAssertFalse(NativePlayerChromeVisibilityPolicy.shouldShowChrome(
            isUserActive: false,
            isPaused: false,
            isBuffering: false,
            showsDiagnostics: false,
            hasError: false
        ))
    }

    func testNativePlayerRemoteControlPolicySeeksWithHorizontalMovesOnly() {
        XCTAssertEqual(
            NativePlayerRemoteControlPolicy.relativeSeekSeconds(for: .left),
            NativePlayerRemoteControlPolicy.rewindSeconds
        )
        XCTAssertEqual(
            NativePlayerRemoteControlPolicy.relativeSeekSeconds(for: .right),
            NativePlayerRemoteControlPolicy.fastForwardSeconds
        )
        XCTAssertNil(NativePlayerRemoteControlPolicy.relativeSeekSeconds(for: .up))
        XCTAssertNil(NativePlayerRemoteControlPolicy.relativeSeekSeconds(for: .down))
    }

    func testNativePlayerRemoteControlPolicyUsesShortDebounceForResponsiveScrubbing() {
        XCTAssertLessThanOrEqual(NativePlayerRemoteControlPolicy.seekCommitDebounceNanoseconds, 350_000_000)
    }

    func testNativePlayerRemoteControlPolicyClampsSeekTargets() {
        XCTAssertEqual(
            NativePlayerRemoteControlPolicy.clampedSeekTarget(from: 12, delta: -30, durationSeconds: 120),
            0
        )
        XCTAssertEqual(
            NativePlayerRemoteControlPolicy.clampedSeekTarget(from: 112, delta: 30, durationSeconds: 120),
            120
        )
        XCTAssertEqual(
            NativePlayerRemoteControlPolicy.clampedSeekTarget(from: 45, delta: 30, durationSeconds: nil),
            75
        )
    }

    func testNativePlayerRemoteControlPolicyTracksForwardAndBackwardSeekCompletion() {
        XCTAssertEqual(NativePlayerRemoteControlPolicy.seekDirection(from: 10, to: 40), .forward)
        XCTAssertEqual(NativePlayerRemoteControlPolicy.seekDirection(from: 40, to: 10), .backward)

        XCTAssertTrue(NativePlayerRemoteControlPolicy.hasReachedSeekTarget(
            reportedSeconds: 42,
            targetSeconds: 40,
            direction: .forward,
            tolerance: 0.75
        ))
        XCTAssertFalse(NativePlayerRemoteControlPolicy.hasReachedSeekTarget(
            reportedSeconds: 38,
            targetSeconds: 40,
            direction: .forward,
            tolerance: 0.75
        ))
        XCTAssertTrue(NativePlayerRemoteControlPolicy.hasReachedSeekTarget(
            reportedSeconds: 8,
            targetSeconds: 10,
            direction: .backward,
            tolerance: 0.75
        ))
        XCTAssertFalse(NativePlayerRemoteControlPolicy.hasReachedSeekTarget(
            reportedSeconds: 12,
            targetSeconds: 10,
            direction: .backward,
            tolerance: 0.75
        ))
    }

    func testAppleNativePlayerDefersAssignmentDuringRenderSurfaceReattach() {
#if os(iOS)
        XCTAssertTrue(NativePlayerViewController.Coordinator.shouldDeferPlayerAssignmentDuringReattach(
            isTemporarilyDetachedForReattach: true,
            controllerPlayerIsNil: true,
            observedPlayerMatches: true
        ))
        XCTAssertFalse(NativePlayerViewController.Coordinator.shouldDeferPlayerAssignmentDuringReattach(
            isTemporarilyDetachedForReattach: true,
            controllerPlayerIsNil: false,
            observedPlayerMatches: true
        ))
        XCTAssertFalse(NativePlayerViewController.Coordinator.shouldDeferPlayerAssignmentDuringReattach(
            isTemporarilyDetachedForReattach: true,
            controllerPlayerIsNil: true,
            observedPlayerMatches: false
        ))
#endif
    }

    func testAppleNativePlayerDoesNotReattachRenderSurfaceOnTVOS() {
        XCTAssertFalse(
            NativePlayerViewController.Coordinator.shouldReattachRenderSurfaceAfterReady(isTVOS: true)
        )
        XCTAssertTrue(
            NativePlayerViewController.Coordinator.shouldReattachRenderSurfaceAfterReady(isTVOS: false)
        )
    }

    func testTVOSPreferredDisplayCriteriaIsDeviceOnly() {
        XCTAssertTrue(NativePlayerViewController.shouldApplyPreferredDisplayCriteriaAutomatically(
            isTVOS: true,
            isSimulator: false
        ))
        XCTAssertFalse(NativePlayerViewController.shouldApplyPreferredDisplayCriteriaAutomatically(
            isTVOS: true,
            isSimulator: true
        ))
        XCTAssertFalse(NativePlayerViewController.shouldApplyPreferredDisplayCriteriaAutomatically(
            isTVOS: false,
            isSimulator: false
        ))
    }

    func testDisplayCriteriaCoordinatorAcceptsOnlyFinitePositiveDurations() {
#if os(tvOS)
        XCTAssertEqual(
            NativeDisplayCriteriaCoordinator.frameDurationSeconds(
                from: CMTime(value: 1, timescale: 24)
            ),
            1.0 / 24.0,
            accuracy: 0.0001
        )
        XCTAssertNil(NativeDisplayCriteriaCoordinator.frameDurationSeconds(from: .zero))
        XCTAssertNil(NativeDisplayCriteriaCoordinator.frameDurationSeconds(from: .invalid))
        XCTAssertNil(NativeDisplayCriteriaCoordinator.frameDurationSeconds(from: .indefinite))
#endif
    }

    private func makePacket(trackID: Int, seconds: Double, keyframe: Bool) -> MediaPacket {
        MediaPacket(
            trackID: trackID,
            timestamp: PacketTimestamp(pts: CMTime(seconds: seconds, preferredTimescale: 1000)),
            isKeyframe: keyframe,
            data: Data([0x01])
        )
    }
}
