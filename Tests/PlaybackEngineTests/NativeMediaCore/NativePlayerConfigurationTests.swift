@testable import ReelFinUI
@testable import PlaybackEngine
import AVFoundation
import CoreMedia
import NativeMediaCore
import Shared
import XCTest

@MainActor
final class NativePlayerConfigurationTests: XCTestCase {
    func testSampleBufferSkipPolicySeeksLocallyForIntroAndDelegatesNextEpisode() {
        let intro = PlaybackSkipSuggestion(
            title: "Skip Intro",
            systemImageName: "forward.frame.fill",
            target: .seek(to: 42.5)
        )
        let nextEpisode = PlaybackSkipSuggestion(
            title: "Next Episode",
            systemImageName: "forward.end.fill",
            target: .nextEpisode
        )

        XCTAssertEqual(NativePlayerSampleBufferSkipPolicy.localSeekTarget(for: intro), 42.5)
        XCTAssertNil(NativePlayerSampleBufferSkipPolicy.localSeekTarget(for: nextEpisode))
    }

    func testMatroskaInvalidatedReadStillCancelsAndClearsSourceExactlyOnce() async throws {
        let factory = InvalidationResumeByteSourceFactory()
        let controller = NativeMatroskaSampleBufferPlayerController {
            factory.make(url: $0, headers: $1)
        }
        controller.beforePlaybackTaskCancellation = {
            factory.source?.resumeInitialRead()
            try? await Task.sleep(for: .milliseconds(100))
        }
        _ = controller.view
        controller.configure(
            url: URL(fileURLWithPath: "/tmp/native-\(UUID().uuidString).mkv"),
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
        let sourceWasCreated = await waitUntil { factory.source != nil }
        XCTAssertTrue(sourceWasCreated)
        var source: InvalidationResumeByteSource? = try XCTUnwrap(factory.source)
        let readSuspended = await waitUntil { source?.hasSuspendedInitialRead == true }
        XCTAssertTrue(readSuspended)

        controller.stopForDismantle()

        let becameIdle = await waitUntil { controller.readerPhase == .idle }
        XCTAssertTrue(becameIdle)
        XCTAssertEqual(source?.cancelCount, 1)
        weak var weakSource = source
        factory.releaseSource()
        source = nil
        let sourceWasCleared = await waitUntil { weakSource == nil }
        XCTAssertTrue(sourceWasCleared)
    }

    func testMatroskaStopThenReconfigureSharesOneSuspendedRetirement() async throws {
        let factory = SuspendingCancellationByteSourceFactory()
        let controller = NativeMatroskaSampleBufferPlayerController {
            factory.make(url: $0, headers: $1)
        }
        _ = controller.view
        let firstURL = URL(fileURLWithPath: "/tmp/native-\(UUID().uuidString).mkv")
        controller.configure(
            url: firstURL,
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
        let firstReaderBecameActive = await waitUntil { controller.readerPhase == .active }
        XCTAssertTrue(firstReaderBecameActive)
        let firstSource = try XCTUnwrap(factory.firstSource)

        controller.stopForDismantle()
        let firstCancellationStarted = await firstSource.waitForCancellationStart()
        XCTAssertTrue(firstCancellationStarted)
        controller.configure(
            url: URL(fileURLWithPath: "/tmp/native-\(UUID().uuidString).mkv"),
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
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(factory.sourceCount, 1)
        XCTAssertFalse(controller.teardownEvents.contains(.renderersFlushed))

        await firstSource.resumeCancellation()

        let replacementBecameActive = await waitUntil {
            controller.readerPhase == .active && factory.sourceCount == 2
        }
        XCTAssertTrue(replacementBecameActive)
        let firstCancelCount = await firstSource.cancelCount
        XCTAssertEqual(firstCancelCount, 1)
        XCTAssertEqual(controller.teardownEvents.filter { $0 == .readerFinished }.count, 1)
        XCTAssertEqual(controller.teardownEvents.filter { $0 == .renderersFlushed }.count, 1)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(controller.teardownEvents.filter { $0 == .renderersFlushed }.count, 1)
        controller.stopForDismantle()
    }

    func testMatroskaDismantleRetainsCleanupUntilQueuesFlush() async throws {
        let factory = RetainedFinishedByteSourceFactory()
        let recorder = MatroskaLifecycleRecorder()
        var controller: NativeMatroskaSampleBufferPlayerController? =
            NativeMatroskaSampleBufferPlayerController {
                factory.make(url: $0, headers: $1)
            }
        controller?.teardownEventObserver = { recorder.record($0) }
        _ = controller?.view
        controller?.configure(
            url: URL(fileURLWithPath: "/tmp/native-\(UUID().uuidString).mkv"),
            headers: [:],
            container: .matroska,
            startTimeSeconds: 0,
            seekRequest: nil,
            selectedAudioTrackID: nil,
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in recorder.recordCallback() },
            onPlaybackTime: { _ in recorder.recordCallback() }
        )
        let readerFinished = await waitUntil { controller?.readerPhase == .retiring }
        XCTAssertTrue(readerFinished)
        var source: FinishedByteSource? = try XCTUnwrap(factory.source)
        let sourceCancelCount = await source?.cancelCount
        XCTAssertEqual(sourceCancelCount, 1)

        recorder.markDismantled()
        controller?.stopForDismantle()
        weak var weakController = controller
        weak var weakSource = source
        controller = nil
        XCTAssertNotNil(weakController)
        factory.releaseSource()
        source = nil

        let cleanupFlushed = await waitUntil { recorder.didFlushRenderers }
        XCTAssertTrue(cleanupFlushed)
        let resourcesReleased = await waitUntil { weakController == nil && weakSource == nil }
        XCTAssertTrue(resourcesReleased)
        XCTAssertEqual(recorder.callbackCountAfterDismantle, 0)
    }

    func testMatroskaReplacementCancelsSourceAndQuiescesBeforeRendererFlush() async throws {
        let factory = RecordingByteSourceFactory()
        let controller = NativeMatroskaSampleBufferPlayerController {
            factory.make(url: $0, headers: $1)
        }
        _ = controller.view
        let url = URL(fileURLWithPath: "/tmp/native-\(UUID().uuidString).mkv")

        controller.configure(
            url: url,
            headers: [:],
            container: .matroska,
            startTimeSeconds: 600,
            seekRequest: nil,
            selectedAudioTrackID: nil,
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )
        let becameActive = await waitUntil { controller.readerPhase == .active }
        XCTAssertTrue(becameActive)
        let firstSource = try XCTUnwrap(factory.source(at: 0))

        controller.configure(
            url: url,
            headers: [:],
            container: .matroska,
            startTimeSeconds: 600,
            seekRequest: NativePlayerSeekRequest(id: 1, targetSeconds: 480),
            selectedAudioTrackID: nil,
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )

        let replacementBecameActive = await waitUntil {
            controller.readerPhase == .active && factory.sourceCount == 2
        }
        XCTAssertTrue(replacementBecameActive)
        let firstCancelCount = await firstSource.cancelCount
        XCTAssertEqual(firstCancelCount, 1)
        XCTAssertEqual(controller.maximumConcurrentReaderCount, 1)
        XCTAssertEqual(
            controller.teardownEvents,
            [
                .generationInvalidated,
                .sourceCancelled,
                .readerFinished,
                .videoQueueQuiesced,
                .audioQueueQuiesced,
                .renderersFlushed
            ]
        )

        controller.stopForDismantle()
        let becameIdle = await waitUntil { controller.readerPhase == .idle }
        XCTAssertTrue(becameIdle)
        let secondSource = try XCTUnwrap(factory.source(at: 1))
        let secondCancelCount = await secondSource.cancelCount
        XCTAssertEqual(secondCancelCount, 1)
        XCTAssertEqual(controller.callbackCountAfterDismantle, 0)
    }

    func testNativePlaybackPreparationCancelsTemporaryProbeSource() async throws {
        let itemID = "probe-source-cancel"
        let mediaSource = MediaSource(
            id: "probe-source",
            itemID: itemID,
            name: "Probe Source",
            fileSize: Int64(RecordingByteSourceFactory.matroskaBootstrapData.count),
            container: "mkv",
            videoCodec: "h264",
            supportsDirectPlay: false,
            supportsDirectStream: false
        )
        let apiClient = ProbePlaybackAPIClient(source: mediaSource)
        let source = FinishedByteSource(
            url: URL(string: "https://example.com/Videos/\(itemID)/stream.mkv")!,
            data: RecordingByteSourceFactory.matroskaBootstrapData
        )
        let controller = NativePlayerPlaybackController(
            apiClient: apiClient,
            byteSourceFactory: { _, _ in source }
        )
        let nativeConfig = NativePlayerConfig(enabled: true, surfacePreference: .customPlayer)

        _ = try await controller.prepare(
            itemID: itemID,
            configuration: ServerConfiguration(
                serverURL: URL(string: "https://example.com")!,
                nativePlayerConfig: nativeConfig
            ),
            session: UserSession(userID: "user", username: "user", token: "secret"),
            nativeConfig: nativeConfig,
            startTimeTicks: nil
        )

        let cancelCount = await source.cancelCount
        XCTAssertEqual(cancelCount, 1)
    }

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

    func testMatroskaForwardSeekKeepsCurrentReaderAndCoalescesRequest() async {
        let factory = RecordingByteSourceFactory()
        let controller = NativeMatroskaSampleBufferPlayerController {
            factory.make(url: $0, headers: $1)
        }
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
        let becameActive = await waitUntil { controller.readerPhase == .active }
        XCTAssertTrue(becameActive)
        XCTAssertEqual(factory.sourceCount, 1)
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
        XCTAssertEqual(factory.sourceCount, 1)

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
        XCTAssertEqual(factory.sourceCount, 1)
        controller.stopForDismantle()
    }

    func testMatroskaAlternatingSeekKeepsOnlyLatestTarget() async {
        let factory = RecordingByteSourceFactory()
        let controller = NativeMatroskaSampleBufferPlayerController {
            factory.make(url: $0, headers: $1)
        }
        _ = controller.view
        let url = URL(fileURLWithPath: "/tmp/native-\(UUID().uuidString).mkv")

        controller.configure(
            url: url,
            headers: [:],
            container: .matroska,
            startTimeSeconds: 600,
            seekRequest: nil,
            selectedAudioTrackID: nil,
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )
        let becameActive = await waitUntil { controller.readerPhase == .active }
        XCTAssertTrue(becameActive)
        XCTAssertEqual(factory.sourceCount, 1)

        controller.configure(
            url: url,
            headers: [:],
            container: .matroska,
            startTimeSeconds: 600,
            seekRequest: NativePlayerSeekRequest(id: 1, targetSeconds: 480),
            selectedAudioTrackID: nil,
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )
        controller.configure(
            url: url,
            headers: [:],
            container: .matroska,
            startTimeSeconds: 600,
            seekRequest: NativePlayerSeekRequest(id: 2, targetSeconds: 700),
            selectedAudioTrackID: nil,
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )

        XCTAssertEqual(controller.readerPhase, .retiring)
        XCTAssertEqual(controller.pendingRestartTargetSeconds, 700)
        XCTAssertEqual(factory.sourceCount, 1)

        let replacementBecameActive = await waitUntil {
            controller.readerPhase == .active && factory.sourceCount == 2
        }
        XCTAssertTrue(replacementBecameActive)
        controller.stopForDismantle()
    }

    func testMatroskaEOFRetainsCallbackOwnershipForFinalDiagnosticsAndDrains() async {
        let factory = FinishedByteSourceFactory()
        let controller = NativeMatroskaSampleBufferPlayerController {
            factory.make(url: $0, headers: $1)
        }
        _ = controller.view
        let url = URL(fileURLWithPath: "/tmp/native-\(UUID().uuidString).mkv")
        var diagnostics: [[String]] = []

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
            onDiagnostics: { diagnostics.append($0) },
            onPlaybackTime: { _ in }
        )

        let deliveredFinalDiagnostics = await waitUntil {
            diagnostics.contains { $0.contains("state=ended") }
        }

        XCTAssertTrue(deliveredFinalDiagnostics)
        XCTAssertEqual(controller.readerPhase, .retiring)
        XCTAssertFalse(controller.readerCanSeekInPlace)
        XCTAssertTrue(controller.readerOwnsCurrentCallbacks)
        controller.stopForDismantle()
        let becameIdle = await waitUntil { controller.readerPhase == .idle }
        XCTAssertTrue(becameIdle)
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

    func testMatroskaSeekCommitPolicyPreservesSeekToZero() {
        var policy = NativePlayerSeekCommitPolicy()

        XCTAssertTrue(policy.enqueueRestart(targetSeconds: 0))
        let commit = policy.takePendingRestart()

        XCTAssertEqual(commit?.targetSeconds, 0)
    }

    func testMatroskaSeekCommitPolicyCoalescesRapidBackwardRestartsToLatestTarget() {
        var policy = NativePlayerSeekCommitPolicy()

        XCTAssertTrue(policy.enqueueRestart(targetSeconds: 480))
        XCTAssertFalse(policy.enqueueRestart(targetSeconds: 240))
        XCTAssertFalse(policy.enqueueRestart(targetSeconds: 0))

        let commit = policy.takePendingRestart()
        XCTAssertEqual(commit?.targetSeconds, 0)
        XCTAssertEqual(commit?.generation, 3)
        policy.finishRestart()
        XCTAssertFalse(policy.isRestartInFlight)
    }

    func testMatroskaSeekCommitPolicyRejectsStaleGenerationCallbacks() {
        var policy = NativePlayerSeekCommitPolicy()

        _ = policy.enqueueRestart(targetSeconds: 480)
        let staleGeneration = policy.generation
        _ = policy.enqueueRestart(targetSeconds: 0)

        XCTAssertFalse(policy.ownsCallbacks(from: staleGeneration))
        XCTAssertTrue(policy.ownsCallbacks(from: policy.generation))
    }

    func testMatroskaControllerKeepsOneLatestRestartWithPauseAndTrackSelection() {
        let controller = NativeMatroskaSampleBufferPlayerController()
        _ = controller.view
        let url = URL(fileURLWithPath: "/tmp/native-\(UUID().uuidString).mkv")

        controller.configure(
            url: url,
            headers: [:],
            container: .matroska,
            startTimeSeconds: 600,
            seekRequest: nil,
            selectedAudioTrackID: "1",
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )
        controller.configure(
            url: url,
            headers: [:],
            container: .matroska,
            startTimeSeconds: 600,
            seekRequest: NativePlayerSeekRequest(id: 1, targetSeconds: 480),
            selectedAudioTrackID: "1",
            selectedSubtitleTrackID: nil,
            baseDiagnostics: [],
            isPaused: true,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )
        controller.configure(
            url: url,
            headers: [:],
            container: .matroska,
            startTimeSeconds: 600,
            seekRequest: NativePlayerSeekRequest(id: 2, targetSeconds: 240),
            selectedAudioTrackID: "2",
            selectedSubtitleTrackID: "3",
            baseDiagnostics: [],
            isPaused: true,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )
        controller.configure(
            url: url,
            headers: [:],
            container: .matroska,
            startTimeSeconds: 600,
            seekRequest: NativePlayerSeekRequest(id: 3, targetSeconds: 0),
            selectedAudioTrackID: "2",
            selectedSubtitleTrackID: "3",
            baseDiagnostics: [],
            isPaused: true,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )

        XCTAssertEqual(controller.restartCoordinatorStartCount, 1)
        XCTAssertEqual(controller.pendingRestartTargetSeconds, 0)
        XCTAssertTrue(controller.pendingRestartIsPaused)
        XCTAssertEqual(controller.pendingRestartSelectedAudioTrackID, "2")
        XCTAssertEqual(controller.pendingRestartSelectedSubtitleTrackID, "3")
        controller.stopForDismantle()
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
            headers: [:],
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
            headers: [:],
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

    func testNativePlayerChromeVisibilityPolicyPinsAutomationChrome() {
        XCTAssertTrue(NativePlayerChromeVisibilityPolicy.shouldShowChrome(
            isUserActive: false,
            isPaused: false,
            isBuffering: false,
            showsDiagnostics: false,
            hasError: false,
            isPinnedForAutomation: true
        ))
        XCTAssertFalse(NativePlayerChromeVisibilityPolicy.shouldAutoHide(
            isPaused: false,
            isBuffering: false,
            showsDiagnostics: false,
            hasError: false,
            isPinnedForAutomation: true
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

    func testAppleNativePlayerForwardsReadyForDisplayOnlyAfterItemReady() {
        XCTAssertFalse(NativePlayerViewController.Coordinator.shouldForwardReadyForDisplay(
            controllerIsReadyForDisplay: true,
            itemStatus: .unknown,
            isRenderSurfaceReattaching: false
        ))
        XCTAssertFalse(NativePlayerViewController.Coordinator.shouldForwardReadyForDisplay(
            controllerIsReadyForDisplay: false,
            itemStatus: .readyToPlay,
            isRenderSurfaceReattaching: false
        ))
        XCTAssertFalse(NativePlayerViewController.Coordinator.shouldForwardReadyForDisplay(
            controllerIsReadyForDisplay: true,
            itemStatus: .readyToPlay,
            isRenderSurfaceReattaching: true
        ))
        XCTAssertTrue(NativePlayerViewController.Coordinator.shouldForwardReadyForDisplay(
            controllerIsReadyForDisplay: true,
            itemStatus: .readyToPlay,
            isRenderSurfaceReattaching: false
        ))
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

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

private final class RecordingByteSourceFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [BlockingByteSource] = []

    func make(url: URL, headers: [String: String]) -> any MediaByteSource {
        _ = headers
        let source = BlockingByteSource(url: url, bootstrapData: Self.matroskaBootstrapData)
        lock.withLock { sources.append(source) }
        return source
    }

    var sourceCount: Int { lock.withLock { sources.count } }

    func source(at index: Int) -> BlockingByteSource? {
        lock.withLock { sources.indices.contains(index) ? sources[index] : nil }
    }

    fileprivate static let matroskaBootstrapData: Data = {
        let avcC: [UInt8] = [
            0x01, 0x42, 0xE0, 0x1E, 0xFF, 0xE1,
            0x00, 0x1D,
            0x67, 0x42, 0xE0, 0x1E, 0xDA, 0x02, 0x80, 0xB7,
            0xFE, 0x5C, 0x05, 0xA8, 0x30, 0x30, 0x32, 0x00,
            0x00, 0x03, 0x00, 0x02, 0x00, 0x00, 0x03, 0x00,
            0x79, 0x1E, 0x2C, 0x5C, 0x90,
            0x01, 0x00, 0x04,
            0x68, 0xCE, 0x06, 0xE2
        ]
        let videoTrack = element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x01]) +
            element([0x86], payload: Array("V_MPEG4/ISO/AVC".utf8)) +
            element([0x63, 0xA2], payload: avcC)
        )
        let tracks = element([0x16, 0x54, 0xAE, 0x6B], payload: videoTrack)
        return Data(element([0x1A, 0x45, 0xDF, 0xA3], payload: []))
            + Data([0x18, 0x53, 0x80, 0x67, 0xFF])
            + Data(tracks)
    }()

    private static func element(_ id: [UInt8], payload: [UInt8]) -> [UInt8] {
        id + vintSize(payload.count) + payload
    }

    private static func vintSize(_ size: Int) -> [UInt8] {
        precondition(size < 16_383)
        return size < 127
            ? [UInt8(0x80 | size)]
            : [UInt8(0x40 | ((size >> 8) & 0x3F)), UInt8(size & 0xFF)]
    }
}

private final class InvalidationResumeByteSourceFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var retainedSource: InvalidationResumeByteSource?

    var source: InvalidationResumeByteSource? { lock.withLock { retainedSource } }

    func make(url: URL, headers: [String: String]) -> any MediaByteSource {
        _ = headers
        return lock.withLock {
            if let retainedSource { return retainedSource }
            let source = InvalidationResumeByteSource(url: url)
            retainedSource = source
            return source
        }
    }

    func releaseSource() {
        lock.withLock { retainedSource = nil }
    }
}

private final class InvalidationResumeByteSource: MediaByteSource, @unchecked Sendable {
    nonisolated let url: URL
    private let lock = NSLock()
    private var initialReadContinuation: CheckedContinuation<Data, Error>?
    private var didServeInitialRead = false
    private var _cancelCount = 0

    init(url: URL) {
        self.url = url
    }

    var hasSuspendedInitialRead: Bool { lock.withLock { initialReadContinuation != nil } }
    var cancelCount: Int { lock.withLock { _cancelCount } }

    func read(range: ByteRange) async throws -> Data {
        if lock.withLock({ !didServeInitialRead }) {
            return try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    didServeInitialRead = true
                    initialReadContinuation = continuation
                }
            }
        }
        while true {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func resumeInitialRead() {
        let continuation = lock.withLock {
            defer { initialReadContinuation = nil }
            return initialReadContinuation
        }
        continuation?.resume(returning: RecordingByteSourceFactory.matroskaBootstrapData)
    }

    func size() async throws -> Int64? { 16 * 1_024 * 1_024 }
    func cancel() async { lock.withLock { _cancelCount += 1 } }
    func metrics() async -> MediaAccessMetrics { MediaAccessMetrics() }
}

private final class SuspendingCancellationByteSourceFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [any MediaByteSource] = []
    private var first: SuspendingCancellationByteSource?

    var firstSource: SuspendingCancellationByteSource? { lock.withLock { first } }
    var sourceCount: Int { lock.withLock { sources.count } }

    func make(url: URL, headers: [String: String]) -> any MediaByteSource {
        _ = headers
        return lock.withLock {
            if sources.isEmpty {
                let source = SuspendingCancellationByteSource(
                    url: url,
                    bootstrapData: RecordingByteSourceFactory.matroskaBootstrapData
                )
                first = source
                sources.append(source)
                return source
            }
            let source = BlockingByteSource(
                url: url,
                bootstrapData: RecordingByteSourceFactory.matroskaBootstrapData
            )
            sources.append(source)
            return source
        }
    }

    func releaseSources() {
        lock.withLock {
            sources.removeAll()
            first = nil
        }
    }
}

private actor SuspendingCancellationByteSource: MediaByteSource {
    nonisolated let url: URL
    private let bootstrapData: Data
    private var servedBootstrap = false
    private var readsShouldFinish = false
    private var cancellationContinuation: CheckedContinuation<Void, Never>?
    private var cancellationCanFinish = false
    private(set) var cancelCount = 0
    private var cancellationStarted = false

    init(url: URL, bootstrapData: Data) {
        self.url = url
        self.bootstrapData = bootstrapData
    }

    func read(range: ByteRange) async throws -> Data {
        if range.offset == 0, !servedBootstrap {
            servedBootstrap = true
            return bootstrapData
        }
        while !readsShouldFinish {
            try await Task.sleep(for: .milliseconds(20))
        }
        return Data()
    }

    func size() async throws -> Int64? { 16 * 1_024 * 1_024 }

    func cancel() async {
        cancelCount += 1
        cancellationStarted = true
        guard !cancellationCanFinish else { return }
        await withCheckedContinuation { continuation in
            cancellationContinuation = continuation
        }
    }

    func waitForCancellationStart() async -> Bool {
        for _ in 0..<100 {
            if cancellationStarted { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return cancellationStarted
    }

    func resumeCancellation() {
        cancellationCanFinish = true
        cancellationContinuation?.resume()
        cancellationContinuation = nil
    }

    func finishReads() {
        readsShouldFinish = true
    }

    func metrics() async -> MediaAccessMetrics { MediaAccessMetrics() }
}

private final class MatroskaLifecycleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [NativeMatroskaTeardownEvent] = []
    private var dismantled = false
    private var lateCallbacks = 0

    var didFlushRenderers: Bool { lock.withLock { events.contains(.renderersFlushed) } }
    var callbackCountAfterDismantle: Int { lock.withLock { lateCallbacks } }

    func record(_ event: NativeMatroskaTeardownEvent) {
        lock.withLock { events.append(event) }
    }

    func markDismantled() {
        lock.withLock { dismantled = true }
    }

    func recordCallback() {
        lock.withLock {
            if dismantled { lateCallbacks += 1 }
        }
    }
}

private final class FinishedByteSourceFactory: @unchecked Sendable {
    func make(url: URL, headers: [String: String]) -> any MediaByteSource {
        _ = headers
        return FinishedByteSource(
            url: url,
            data: RecordingByteSourceFactory.matroskaBootstrapData
        )
    }
}

private final class RetainedFinishedByteSourceFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var retainedSource: FinishedByteSource?

    var source: FinishedByteSource? { lock.withLock { retainedSource } }

    func make(url: URL, headers: [String: String]) -> any MediaByteSource {
        _ = headers
        let source = FinishedByteSource(
            url: url,
            data: RecordingByteSourceFactory.matroskaBootstrapData
        )
        lock.withLock { retainedSource = source }
        return source
    }

    func releaseSource() {
        lock.withLock { retainedSource = nil }
    }
}

private actor FinishedByteSource: MediaByteSource {
    nonisolated let url: URL
    private let data: Data
    private(set) var cancelCount = 0

    init(url: URL, data: Data) {
        self.url = url
        self.data = data
    }

    func read(range: ByteRange) async throws -> Data {
        guard range.offset >= 0, range.length >= 0 else {
            throw MediaAccessError.invalidRange(range)
        }
        guard range.offset < Int64(data.count) else { return Data() }
        let lowerBound = Int(range.offset)
        let upperBound = lowerBound + min(range.length, data.count - lowerBound)
        return Data(data[lowerBound..<upperBound])
    }

    func size() async throws -> Int64? { Int64(data.count) }
    func cancel() async { cancelCount += 1 }
    func metrics() async -> MediaAccessMetrics { MediaAccessMetrics() }
}

private final class ProbePlaybackAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    let source: MediaSource

    init(source: MediaSource) {
        self.source = source
    }

    func currentConfiguration() async -> ServerConfiguration? { nil }
    func currentSession() async -> UserSession? { nil }
    func configure(server: ServerConfiguration) async throws {}
    func testConnection(serverURL: URL) async throws {}
    func authenticate(credentials: UserCredentials) async throws -> UserSession { throw AppError.unknown }
    func signOut() async {}
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState { throw AppError.unknown }
    func pollQuickConnect(secret: String) async throws -> UserSession? { nil }
    func fetchUserViews() async throws -> [Shared.LibraryView] { [] }
    func fetchHomeFeed(since: Date?) async throws -> HomeFeed { .empty }
    func fetchItem(id: String) async throws -> MediaItem { throw AppError.unknown }
    func fetchItemDetail(id: String) async throws -> MediaDetail { throw AppError.unknown }
    func fetchSeasons(seriesID: String) async throws -> [MediaItem] { [] }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] { [] }
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? { nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { [] }
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] { [source] }
    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] { [source] }
    func fetchTrickplayManifest(itemID: String, mediaSourceID: String?) async throws -> TrickplayManifest? { nil }
    func trickplayTileBaseURL(itemID: String, mediaSourceID: String?, width: Int) async -> URL? { nil }
    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? { nil }
    func reportPlayback(progress: PlaybackProgressUpdate) async throws {}
    func reportPlaybackStopped(progress: PlaybackProgressUpdate) async throws {}
    func reportPlayed(itemID: String) async throws {}
    func setPlayedState(itemID: String, isPlayed: Bool) async throws {}
    func setFavorite(itemID: String, isFavorite: Bool) async throws {}
}

private actor BlockingByteSource: MediaByteSource {
    nonisolated let url: URL
    private let bootstrapData: Data
    private var servedBootstrap = false
    private(set) var cancelCount = 0
    private var cancelled = false

    init(url: URL, bootstrapData: Data) {
        self.url = url
        self.bootstrapData = bootstrapData
    }

    func read(range: ByteRange) async throws -> Data {
        if range.offset == 0, !servedBootstrap {
            servedBootstrap = true
            return bootstrapData
        }
        while !cancelled {
            try await Task.sleep(for: .milliseconds(20))
        }
        throw MediaAccessError.cancelled
    }

    func size() async throws -> Int64? { 16 * 1_024 * 1_024 }
    func cancel() async { cancelCount += 1; cancelled = true }
    func metrics() async -> MediaAccessMetrics { MediaAccessMetrics() }
}
