import XCTest
@testable import PlaybackEngine

final class PlaybackResumeSeekPlannerTests: XCTestCase {
    func testDoesNotSeekWhenCurrentPlayerTimeAlreadyMatchesResume() {
        XCTAssertFalse(
            PlaybackResumeSeekPlanner.shouldApplySeek(
                pendingResumeSeconds: 132,
                currentPlayerTime: 130.8,
                currentItemDuration: 1_200,
                currentMediaRuntimeSeconds: 1_320
            )
        )
    }

    func testDoesNotSeekWhenStreamDurationMatchesExpectedRemainingRuntime() {
        XCTAssertFalse(
            PlaybackResumeSeekPlanner.shouldApplySeek(
                pendingResumeSeconds: 180,
                currentPlayerTime: 0.6,
                currentItemDuration: 1_620,
                currentMediaRuntimeSeconds: 1_800
            )
        )
    }

    func testSeeksWhenStreamDurationLooksLikeFullRuntime() {
        XCTAssertTrue(
            PlaybackResumeSeekPlanner.shouldApplySeek(
                pendingResumeSeconds: 180,
                currentPlayerTime: 0.4,
                currentItemDuration: 1_800,
                currentMediaRuntimeSeconds: 1_800
            )
        )
    }

    func testDoesNotSeekAfterFirstFrameForResumeBasedTranscode() {
        XCTAssertFalse(
            PlaybackResumeSeekPlanner.shouldApplySeek(
                pendingResumeSeconds: 2_325.5,
                currentPlayerTime: 0.4,
                currentItemDuration: nil,
                currentMediaRuntimeSeconds: 7_200,
                transcodeStartOffset: 2_325.5
            )
        )
    }

    func testDetectsServerOffsetStreamWhenDurationMatchesRemainingRuntime() {
        XCTAssertTrue(
            PlaybackResumeSeekPlanner.streamLooksServerOffset(
                pendingResumeSeconds: 180,
                currentPlayerTime: 0.4,
                currentItemDuration: 1_620,
                currentMediaRuntimeSeconds: 1_800
            )
        )
    }

    func testDoesNotTreatFullRuntimeStreamAsServerOffset() {
        XCTAssertFalse(
            PlaybackResumeSeekPlanner.streamLooksServerOffset(
                pendingResumeSeconds: 180,
                currentPlayerTime: 0.4,
                currentItemDuration: 1_800,
                currentMediaRuntimeSeconds: 1_800
            )
        )
    }
}
