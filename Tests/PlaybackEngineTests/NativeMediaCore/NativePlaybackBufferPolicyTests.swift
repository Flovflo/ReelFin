@testable import ReelFinUI
import XCTest

final class NativePlaybackBufferPolicyTests: XCTestCase {
    func testMatroskaStartupWatchdogIsBoundedForFastVideoStart() {
        let policy = NativePlaybackBufferPolicy.matroska

        XCTAssertEqual(policy.maximumAudioStartupWaitSeconds, 4.0)
    }

    func testMatroskaInitialBufferRequiresFastAudioAhead() {
        let policy = NativePlaybackBufferPolicy.matroska

        let thinAudio = NativePlaybackBufferSnapshot(
            startTime: 20,
            currentVideoPTS: 23,
            currentAudioPTS: 20.5,
            playbackTime: 20,
            videoQueuedSeconds: 0,
            audioQueuedSeconds: 0,
            videoPacketCount: 80,
            audioPacketCount: 32,
            videoPrimedPacketCount: 80,
            audioPrimedPacketCount: 32
        )

        let decision = policy.decision(
            snapshot: thinAudio,
            needsAudio: true,
            isRebuffering: false
        )

        XCTAssertFalse(decision.canStart)
        XCTAssertEqual(decision.requiredAudioAheadSeconds, 1.25)
    }

    func testMatroskaInitialBufferDoesNotStartBeforeAudioRendererIsPrimed() {
        let policy = NativePlaybackBufferPolicy.matroska

        let queuedButNotRendered = NativePlaybackBufferSnapshot(
            startTime: 20,
            currentVideoPTS: 23,
            currentAudioPTS: 20,
            playbackTime: 20,
            videoQueuedSeconds: 2.0,
            audioQueuedSeconds: 8.5,
            videoPacketCount: 24,
            audioPacketCount: 0,
            videoPrimedPacketCount: 24,
            audioPrimedPacketCount: 0
        )

        let decision = policy.decision(
            snapshot: queuedButNotRendered,
            needsAudio: true,
            isRebuffering: false
        )

        XCTAssertFalse(decision.canStart)
        XCTAssertGreaterThanOrEqual(decision.audioAheadSeconds, 8.0)
    }

    func testMatroskaInitialBufferDoesNotStartWithOneRendererAudioPacket() {
        let policy = NativePlaybackBufferPolicy.matroska

        let rendererBarelyPrimed = NativePlaybackBufferSnapshot(
            startTime: 21.248,
            currentVideoPTS: 24.9,
            currentAudioPTS: 21.248,
            playbackTime: 21.248,
            videoQueuedSeconds: 3.7,
            audioQueuedSeconds: 9.6,
            videoPacketCount: 49,
            audioPacketCount: 1,
            videoPrimedPacketCount: 49,
            audioPrimedPacketCount: 1
        )

        let decision = policy.decision(
            snapshot: rendererBarelyPrimed,
            needsAudio: true,
            isRebuffering: false
        )

        XCTAssertFalse(decision.canStart)
        XCTAssertEqual(decision.requiredAudioPrimedPacketCount, 8)
        XCTAssertGreaterThanOrEqual(decision.audioAheadSeconds, 9.0)
    }

    func testMatroskaInitialBufferStartsWithFastRendererPriming() {
        let policy = NativePlaybackBufferPolicy.matroska

        let buffered = NativePlaybackBufferSnapshot(
            startTime: 20,
            currentVideoPTS: 21.5,
            currentAudioPTS: 21.6,
            playbackTime: 20,
            videoQueuedSeconds: 0,
            audioQueuedSeconds: 0,
            videoPacketCount: 12,
            audioPacketCount: 8,
            videoPrimedPacketCount: 12,
            audioPrimedPacketCount: 8
        )

        let decision = policy.decision(
            snapshot: buffered,
            needsAudio: true,
            isRebuffering: false
        )

        XCTAssertTrue(decision.canStart)
        XCTAssertGreaterThanOrEqual(decision.audioAheadSeconds, 1.25)
        XCTAssertEqual(decision.requiredAudioPrimedPacketCount, 8)
    }

    func testMatroskaInitialBufferStartsWhenDolbyRendererSaturatesBelowDeepPacketCount() {
        let policy = NativePlaybackBufferPolicy.matroska

        let dolbySaturated = NativePlaybackBufferSnapshot(
            startTime: 0,
            currentVideoPTS: 9.55,
            currentAudioPTS: 9.85,
            playbackTime: 0,
            videoQueuedSeconds: 0,
            audioQueuedSeconds: 0,
            videoPacketCount: 50,
            audioPacketCount: 24,
            videoPrimedPacketCount: 50,
            audioPrimedPacketCount: 24
        )

        let decision = policy.decision(
            snapshot: dolbySaturated,
            needsAudio: true,
            isRebuffering: false
        )

        XCTAssertTrue(decision.canStart)
        XCTAssertEqual(decision.requiredAudioPrimedPacketCount, 8)
    }

    func testMatroskaInitialBufferDoesNotDeadlockWaitingPastRendererPrerollLimit() {
        let policy = NativePlaybackBufferPolicy.matroska

        let rendererPrerollLimit = NativePlaybackBufferSnapshot(
            startTime: 21.248,
            currentVideoPTS: 27.1,
            currentAudioPTS: 29.5,
            playbackTime: 21.248,
            videoQueuedSeconds: 0,
            audioQueuedSeconds: 0,
            videoPacketCount: 420,
            audioPacketCount: 32,
            videoPrimedPacketCount: 420,
            audioPrimedPacketCount: 32
        )

        let decision = policy.decision(
            snapshot: rendererPrerollLimit,
            needsAudio: true,
            isRebuffering: false
        )

        XCTAssertTrue(decision.canStart)
        XCTAssertEqual(decision.requiredAudioPrimedPacketCount, 8)
    }

    func testMatroskaRebufferDoesNotResumeWithZeroAudioAheadDespiteHighPacketCount() {
        let policy = NativePlaybackBufferPolicy.matroska

        let emptyAhead = NativePlaybackBufferSnapshot(
            startTime: 20,
            currentVideoPTS: 28,
            currentAudioPTS: 21.6,
            playbackTime: 21.6,
            videoQueuedSeconds: 3,
            audioQueuedSeconds: 0,
            videoPacketCount: 500,
            audioPacketCount: 680,
            videoPrimedPacketCount: 0,
            audioPrimedPacketCount: 0
        )

        let decision = policy.decision(
            snapshot: emptyAhead,
            needsAudio: true,
            isRebuffering: true
        )

        XCTAssertFalse(decision.canStart)
        XCTAssertEqual(decision.audioAheadSeconds, 0, accuracy: 0.001)
    }

    func testMatroskaAudioRebufferThresholdUsesQueuedAndRenderedAhead() {
        let policy = NativePlaybackBufferPolicy.matroska

        let starved = NativePlaybackBufferSnapshot(
            startTime: 0,
            currentVideoPTS: 30,
            currentAudioPTS: 30.02,
            playbackTime: 30,
            videoQueuedSeconds: 0,
            audioQueuedSeconds: 0,
            videoPacketCount: 500,
            audioPacketCount: 500,
            videoPrimedPacketCount: 500,
            audioPrimedPacketCount: 500
        )
        XCTAssertTrue(policy.shouldRebufferAudio(snapshot: starved, needsAudio: true, isPlaying: true))

        let locallyBuffered = NativePlaybackBufferSnapshot(
            startTime: 0,
            currentVideoPTS: 30,
            currentAudioPTS: 30.02,
            playbackTime: 30,
            videoQueuedSeconds: 0,
            audioQueuedSeconds: 1.0,
            videoPacketCount: 500,
            audioPacketCount: 500,
            videoPrimedPacketCount: 500,
            audioPrimedPacketCount: 500
        )
        XCTAssertFalse(policy.shouldRebufferAudio(snapshot: locallyBuffered, needsAudio: true, isPlaying: true))
    }
}
