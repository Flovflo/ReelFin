import Foundation
@testable import PlaybackEngine
import XCTest

final class PlaybackStartupReadinessPolicyTests: XCTestCase {
    func testRequirementReturnsNilForLowBitrateDirectPlayOnIPhoneWhenNotResuming() {
        let requirement = PlaybackStartupReadinessPolicy.requirement(
            route: .directPlay(URL(string: "https://example.com/video.mp4")!),
            sourceBitrate: 8_000_000,
            runtimeSeconds: nil,
            resumeSeconds: 0,
            isTVOS: false
        )

        XCTAssertNil(requirement)
    }

    func testRequirementBuildsIPhoneResumeDirectPlayPolicy() {
        let requirement = PlaybackStartupReadinessPolicy.requirement(
            route: .directPlay(URL(string: "https://example.com/video.mp4")!),
            sourceBitrate: 1_000_000,
            runtimeSeconds: nil,
            resumeSeconds: 12,
            isTVOS: false
        )

        XCTAssertEqual(requirement?.minimumBufferDuration, 3)
        XCTAssertEqual(requirement?.preferredBufferDuration, 6)
        XCTAssertEqual(requirement?.timeout, 1.25)
        XCTAssertEqual(requirement?.pollInterval, 0.12)
        XCTAssertEqual(requirement?.reason, "ios_resume_directplay")
    }

    func testRequirementClampsTvOSHighBitrateDirectPlayToRemainingRuntime() {
        let requirement = PlaybackStartupReadinessPolicy.requirement(
            route: .directPlay(URL(string: "https://example.com/video.mp4")!),
            sourceBitrate: 18_000_000,
            runtimeSeconds: 20,
            resumeSeconds: 0,
            isTVOS: true
        )

        XCTAssertEqual(requirement?.minimumBufferDuration, 4)
        XCTAssertEqual(requirement?.preferredBufferDuration, 4)
        XCTAssertEqual(requirement?.timeout, 5)
        XCTAssertEqual(requirement?.pollInterval, 0.15)
        XCTAssertEqual(requirement?.reason, "tvos_high_bitrate_directplay")
    }

    func testRequirementUsesNativeBridgePolicyOnIPhone() {
        let requirement = PlaybackStartupReadinessPolicy.requirement(
            route: .nativeBridge(
                NativeBridgePlan(
                    itemID: "item-1",
                    sourceID: "source-1",
                    sourceURL: URL(string: "https://example.com/video.mkv")!,
                    videoTrack: TrackInfo(id: 1, trackType: .video, codecID: "V_MPEGH/ISO/HEVC", codecName: "hevc", isDefault: true),
                    audioTrack: nil,
                    videoAction: .directPassthrough,
                    audioAction: .directPassthrough,
                    subtitleTracks: [],
                    whyChosen: "test"
                )
            ),
            sourceBitrate: nil,
            runtimeSeconds: nil,
            resumeSeconds: 0,
            isTVOS: false
        )

        XCTAssertEqual(requirement?.minimumBufferDuration, 2)
        XCTAssertEqual(requirement?.preferredBufferDuration, 4)
        XCTAssertEqual(requirement?.timeout, 1)
        XCTAssertEqual(requirement?.pollInterval, 0.12)
        XCTAssertEqual(requirement?.reason, "ios_nativebridge")
    }

    func testRequirementUsesTvOSStreamingPolicyForTranscode() {
        let requirement = PlaybackStartupReadinessPolicy.requirement(
            route: .transcode(URL(string: "https://example.com/master.m3u8")!),
            sourceBitrate: 15_000_000,
            runtimeSeconds: nil,
            resumeSeconds: 0,
            isTVOS: true
        )

        XCTAssertEqual(requirement?.minimumBufferDuration, 8)
        XCTAssertEqual(requirement?.preferredBufferDuration, 18)
        XCTAssertEqual(requirement?.timeout, 3.5)
        XCTAssertEqual(requirement?.pollInterval, 0.15)
        XCTAssertEqual(requirement?.reason, "tvos_hls_startup")
    }

    func testShouldStartAcceptsPreferredBufferBeforeTimeout() {
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 2,
            preferredBufferDuration: 4,
            timeout: 1,
            pollInterval: 0.12,
            reason: "ios_nativebridge"
        )

        XCTAssertTrue(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: 4,
                likelyToKeepUp: false,
                elapsedSeconds: 0.5,
                requirement: requirement
            )
        )
    }

    func testShouldStartUsesMinimumAndPollIntervalForIncompleteBuffer() {
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 2,
            preferredBufferDuration: 4,
            timeout: 1,
            pollInterval: 0.12,
            reason: "ios_nativebridge"
        )

        XCTAssertFalse(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: 1.5,
                likelyToKeepUp: false,
                elapsedSeconds: 0.5,
                requirement: requirement
            )
        )

        XCTAssertTrue(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: .infinity,
                likelyToKeepUp: true,
                elapsedSeconds: 0.15,
                requirement: requirement
            )
        )
    }

    func testShouldStartReturnsTrueAfterTimeoutEvenWithLowBuffer() {
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 2,
            preferredBufferDuration: 4,
            timeout: 1,
            pollInterval: 0.12,
            reason: "ios_nativebridge"
        )

        XCTAssertTrue(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: 0,
                likelyToKeepUp: false,
                elapsedSeconds: 1,
                requirement: requirement
            )
        )
    }
}
