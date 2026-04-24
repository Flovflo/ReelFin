@testable import ReelFinUI
import XCTest

final class NativeAudioStartupWatchdogTests: XCTestCase {
    func testDoesNotDegradeBeforeVideoIsReady() {
        var watchdog = NativeAudioStartupWatchdog()
        let snapshot = NativePlaybackBufferSnapshot(
            startTime: 0,
            currentVideoPTS: 1,
            currentAudioPTS: 0,
            playbackTime: 0,
            videoQueuedSeconds: 0,
            audioQueuedSeconds: 0,
            videoPacketCount: 1,
            audioPacketCount: 0,
            videoPrimedPacketCount: 1,
            audioPrimedPacketCount: 0
        )
        let decision = NativePlaybackBufferDecision(
            canStart: false,
            videoAheadSeconds: 1,
            audioAheadSeconds: 0,
            requiredVideoAheadSeconds: 5,
            requiredAudioAheadSeconds: 8,
            requiredAudioPrimedPacketCount: 32
        )

        XCTAssertFalse(watchdog.shouldDegradeAudio(
            now: 100,
            snapshot: snapshot,
            decision: decision,
            needsAudio: true,
            maximumWaitSeconds: 10
        ))
    }

    func testDegradesWhenVideoIsReadyAndAudioNeverPrimes() {
        var watchdog = NativeAudioStartupWatchdog()
        let snapshot = NativePlaybackBufferSnapshot(
            startTime: 0,
            currentVideoPTS: 6,
            currentAudioPTS: 1,
            playbackTime: 0,
            videoQueuedSeconds: 0,
            audioQueuedSeconds: 0,
            videoPacketCount: 120,
            audioPacketCount: 4,
            videoPrimedPacketCount: 120,
            audioPrimedPacketCount: 4
        )
        let decision = NativePlaybackBufferDecision(
            canStart: false,
            videoAheadSeconds: 6,
            audioAheadSeconds: 1,
            requiredVideoAheadSeconds: 5,
            requiredAudioAheadSeconds: 8,
            requiredAudioPrimedPacketCount: 32
        )

        XCTAssertFalse(watchdog.shouldDegradeAudio(
            now: 100,
            snapshot: snapshot,
            decision: decision,
            needsAudio: true,
            maximumWaitSeconds: 10
        ))
        XCTAssertTrue(watchdog.shouldDegradeAudio(
            now: 111,
            snapshot: snapshot,
            decision: decision,
            needsAudio: true,
            maximumWaitSeconds: 10
        ))
    }

    func testResetsWhenAudioBecomesReady() {
        var watchdog = NativeAudioStartupWatchdog()
        let snapshot = NativePlaybackBufferSnapshot(
            startTime: 0,
            currentVideoPTS: 6,
            currentAudioPTS: 1,
            playbackTime: 0,
            videoQueuedSeconds: 0,
            audioQueuedSeconds: 0,
            videoPacketCount: 120,
            audioPacketCount: 4,
            videoPrimedPacketCount: 120,
            audioPrimedPacketCount: 4
        )
        let waitingDecision = NativePlaybackBufferDecision(
            canStart: false,
            videoAheadSeconds: 6,
            audioAheadSeconds: 1,
            requiredVideoAheadSeconds: 5,
            requiredAudioAheadSeconds: 8,
            requiredAudioPrimedPacketCount: 32
        )
        let readyDecision = NativePlaybackBufferDecision(
            canStart: true,
            videoAheadSeconds: 6,
            audioAheadSeconds: 8,
            requiredVideoAheadSeconds: 5,
            requiredAudioAheadSeconds: 8,
            requiredAudioPrimedPacketCount: 32
        )

        _ = watchdog.shouldDegradeAudio(
            now: 100,
            snapshot: snapshot,
            decision: waitingDecision,
            needsAudio: true,
            maximumWaitSeconds: 10
        )
        XCTAssertFalse(watchdog.shouldDegradeAudio(
            now: 111,
            snapshot: snapshot,
            decision: readyDecision,
            needsAudio: true,
            maximumWaitSeconds: 10
        ))
        XCTAssertFalse(watchdog.shouldDegradeAudio(
            now: 112,
            snapshot: snapshot,
            decision: waitingDecision,
            needsAudio: true,
            maximumWaitSeconds: 10
        ))
    }
}
