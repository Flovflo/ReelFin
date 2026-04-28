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

    func testRequirementSkipsLowBitrateIPhoneProgressiveDirectPlayEvenWhenResuming() {
        let requirement = PlaybackStartupReadinessPolicy.requirement(
            route: .directPlay(URL(string: "https://example.com/video.mp4")!),
            sourceBitrate: 1_000_000,
            runtimeSeconds: nil,
            resumeSeconds: 12,
            isTVOS: false
        )

        XCTAssertNil(requirement)
    }

    func testRequirementUsesNoStallGateForIPhoneHighBitrateResume() throws {
        let requirement = PlaybackStartupReadinessPolicy.requirement(
            route: .directPlay(URL(string: "https://example.com/Videos/item/stream?static=true")!),
            sourceBitrate: 22_000_000,
            runtimeSeconds: nil,
            resumeSeconds: 1_039,
            isTVOS: false
        )

        XCTAssertEqual(requirement?.minimumBufferDuration, 24)
        XCTAssertEqual(requirement?.preferredBufferDuration, 24)
        XCTAssertEqual(requirement?.timeout, 24)
        XCTAssertEqual(requirement?.pollInterval, 0.15)
        XCTAssertEqual(requirement?.reason, "ios_resume_directplay_ready")
        XCTAssertEqual(requirement?.allowsTimeoutStart, false)
        XCTAssertFalse(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: 3.3,
                likelyToKeepUp: false,
                elapsedSeconds: 1.1,
                requirement: try XCTUnwrap(requirement)
            )
        )
        XCTAssertFalse(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: 6.7,
                likelyToKeepUp: true,
                elapsedSeconds: 3.25,
                requirement: try XCTUnwrap(requirement)
            )
        )
        XCTAssertFalse(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: 12,
                likelyToKeepUp: true,
                elapsedSeconds: 4,
                requirement: try XCTUnwrap(requirement)
            )
        )
        XCTAssertTrue(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: 24,
                likelyToKeepUp: false,
                elapsedSeconds: 16,
                requirement: try XCTUnwrap(requirement)
            )
        )
        XCTAssertFalse(
            PlaybackStartupReadinessPolicy.allowsImmediateStartBeforeReadyToPlay(
                requirement: try XCTUnwrap(requirement)
            )
        )
    }

    func testIPhoneProgressiveDirectPlayRequiresRangePreheatWhenGuarded() {
        let requiresPreheat = PlaybackStartupReadinessPolicy.requiresStartupPreheat(
            route: .directPlay(URL(string: "https://example.com/video.mp4")!),
            sourceBitrate: 22_000_000,
            runtimeSeconds: nil,
            resumeSeconds: 1_039,
            isTVOS: false
        )

        XCTAssertTrue(requiresPreheat)
    }

    func testTvOSProgressiveDirectPlayRequiresRangePreheatWhenGuarded() {
        let requiresPreheat = PlaybackStartupReadinessPolicy.requiresStartupPreheat(
            route: .directPlay(URL(string: "https://example.com/video.mp4")!),
            sourceBitrate: 22_000_000,
            runtimeSeconds: nil,
            resumeSeconds: 4_655,
            isTVOS: true
        )

        XCTAssertTrue(requiresPreheat)
    }

    func testRequirementSkipsIPhoneHLSStartupGate() {
        let directPlaylistRequirement = PlaybackStartupReadinessPolicy.requirement(
            route: .directPlay(URL(string: "https://example.com/master.m3u8")!),
            sourceBitrate: 12_000_000,
            runtimeSeconds: nil,
            resumeSeconds: 12,
            isTVOS: false
        )
        let transcodeRequirement = PlaybackStartupReadinessPolicy.requirement(
            route: .transcode(URL(string: "https://example.com/main.m3u8")!),
            sourceBitrate: 12_000_000,
            runtimeSeconds: nil,
            resumeSeconds: 12,
            isTVOS: false
        )

        XCTAssertNil(directPlaylistRequirement)
        XCTAssertNil(transcodeRequirement)
    }

    func testRequirementKeepsTvOSHLSStartupGate() {
        let requirement = PlaybackStartupReadinessPolicy.requirement(
            route: .transcode(URL(string: "https://example.com/main.m3u8")!),
            sourceBitrate: 12_000_000,
            runtimeSeconds: nil,
            resumeSeconds: 12,
            isTVOS: true
        )

        XCTAssertEqual(requirement?.minimumBufferDuration, 5)
        XCTAssertEqual(requirement?.preferredBufferDuration, 10)
        XCTAssertEqual(requirement?.timeout, 2.25)
        XCTAssertEqual(requirement?.pollInterval, 0.15)
        XCTAssertEqual(requirement?.reason, "tvos_hls_startup")
    }

    func testRequirementUsesNoStallGateForTvOSHighBitrateDirectPlay() {
        let requirement = PlaybackStartupReadinessPolicy.requirement(
            route: .directPlay(URL(string: "https://example.com/video.mp4")!),
            sourceBitrate: 18_000_000,
            runtimeSeconds: nil,
            resumeSeconds: 0,
            isTVOS: true
        )

        XCTAssertEqual(requirement?.minimumBufferDuration, 4)
        XCTAssertEqual(requirement?.preferredBufferDuration, 12)
        XCTAssertEqual(requirement?.timeout, 6)
        XCTAssertEqual(requirement?.pollInterval, 0.15)
        XCTAssertEqual(requirement?.reason, "tvos_high_bitrate_directplay_ready")
        XCTAssertEqual(requirement?.allowsTimeoutStart, false)
    }

    func testTvOSHighBitrateDirectPlayWaitsForMeasuredBufferTelemetry() throws {
        let requirement = PlaybackStartupReadinessPolicy.requirement(
            route: .directPlay(URL(string: "https://example.com/video.mp4")!),
            sourceBitrate: 22_000_000,
            runtimeSeconds: nil,
            resumeSeconds: 1_102,
            isTVOS: true
        )

        XCTAssertEqual(requirement?.minimumBufferDuration, 4)
        XCTAssertEqual(requirement?.preferredBufferDuration, 12)
        XCTAssertEqual(requirement?.timeout, 6)
        XCTAssertEqual(requirement?.allowsTimeoutStart, false)
        XCTAssertFalse(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: 0,
                likelyToKeepUp: false,
                elapsedSeconds: 0.2,
                requirement: try XCTUnwrap(requirement)
            )
        )
        XCTAssertFalse(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: 0,
                likelyToKeepUp: false,
                elapsedSeconds: 6.1,
                requirement: try XCTUnwrap(requirement)
            )
        )
        XCTAssertFalse(
            PlaybackStartupReadinessPolicy.allowsImmediateStartBeforeReadyToPlay(
                requirement: try XCTUnwrap(requirement)
            )
        )
    }

    func testTvOSHighBitrateDirectPlayStillStartsWithMeasuredBuffer() throws {
        let requirement = try XCTUnwrap(
            PlaybackStartupReadinessPolicy.requirement(
                route: .directPlay(URL(string: "https://example.com/video.mp4")!),
                sourceBitrate: 22_000_000,
                runtimeSeconds: nil,
                resumeSeconds: 1_102,
                isTVOS: true
            )
        )

        XCTAssertTrue(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: 30.1,
                likelyToKeepUp: true,
                elapsedSeconds: 1.5,
                requirement: requirement
            )
        )
        XCTAssertTrue(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: 4,
                likelyToKeepUp: true,
                elapsedSeconds: 1.5,
                requirement: requirement
            )
        )
    }

    func testTvOSLowerBitrateDirectPlayPreservesPermissiveTimeoutStart() throws {
        let requirement = try XCTUnwrap(
            PlaybackStartupReadinessPolicy.requirement(
                route: .directPlay(URL(string: "https://example.com/video.mp4")!),
                sourceBitrate: 8_000_000,
                runtimeSeconds: nil,
                resumeSeconds: 0,
                isTVOS: true
            )
        )

        XCTAssertEqual(requirement.minimumBufferDuration, 0)
        XCTAssertEqual(requirement.preferredBufferDuration, 0)
        XCTAssertEqual(requirement.timeout, 3)
        XCTAssertEqual(requirement.reason, "tvos_directplay_ready")
        XCTAssertEqual(requirement.allowsTimeoutStart, true)
        XCTAssertTrue(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: 0,
                likelyToKeepUp: false,
                elapsedSeconds: 3,
                requirement: requirement
            )
        )
        XCTAssertTrue(
            PlaybackStartupReadinessPolicy.allowsImmediateStartBeforeReadyToPlay(
                requirement: requirement
            )
        )
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
            reason: "ios_nativebridge",
            allowsTimeoutStart: true
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
            reason: "ios_nativebridge",
            allowsTimeoutStart: true
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

    func testShouldStartHonorsTimeoutStartPolicyWithLowBuffer() {
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 2,
            preferredBufferDuration: 4,
            timeout: 1,
            pollInterval: 0.12,
            reason: "ios_nativebridge",
            allowsTimeoutStart: false
        )

        XCTAssertFalse(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: 0,
                likelyToKeepUp: true,
                elapsedSeconds: 1,
                requirement: requirement
            )
        )
    }

    func testShouldStartAcceptsMeasuredBufferAtTimeoutForStrictPolicies() {
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 5,
            preferredBufferDuration: 10,
            timeout: 4,
            pollInterval: 0.15,
            reason: "strict_buffer_guard",
            allowsTimeoutStart: false
        )

        XCTAssertTrue(
            PlaybackStartupReadinessPolicy.shouldStart(
                bufferedDuration: 10.4,
                likelyToKeepUp: true,
                elapsedSeconds: 4.03,
                requirement: requirement
            )
        )
    }

    func testShouldStartPreservesTimeoutStartForPermissivePolicies() {
        let requirement = PlaybackStartupReadinessPolicy.Requirement(
            minimumBufferDuration: 2,
            preferredBufferDuration: 4,
            timeout: 1,
            pollInterval: 0.12,
            reason: "ios_nativebridge",
            allowsTimeoutStart: true
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
