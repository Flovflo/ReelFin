import Foundation
@testable import PlaybackEngine
import XCTest

final class PlaybackDirectPlayStartupPolicyTests: XCTestCase {
    func testIPhoneHighBitrateDirectPlayUsesGuardedModeEvenWhenServerBaselineHasClearFreshHeadroom() {
        let baseline = PlaybackServerNetworkBaseline.Result(
            byteCount: 4 * 1_024 * 1_024,
            elapsedSeconds: 0.42,
            observedBitrate: 79_000_000,
            createdAt: Date(timeIntervalSince1970: 100),
            serverKey: "https://example.com",
            networkScope: "default"
        )

        let decision = DirectPlayStartupPolicy.decision(
            route: .directPlay(URL(string: "https://example.com/Videos/item/stream.mp4?static=true")!),
            sourceBitrate: 21_868_794,
            itemPreheatResult: nil,
            serverBaselineResult: baseline,
            isTVOS: false,
            now: Date(timeIntervalSince1970: 120)
        )

        XCTAssertEqual(decision.mode, .guarded)
        XCTAssertEqual(decision.minimumBufferDuration, 20)
        XCTAssertEqual(decision.preferredBufferDuration, 30)
        XCTAssertEqual(decision.timeout, 45)
        XCTAssertFalse(decision.allowsTimeoutStart)
        XCTAssertNil(decision.failureReason)
    }

    func testTvOSHighBitrateDirectPlayCanUseFastModeWhenServerBaselineHasClearFreshHeadroom() {
        let baseline = PlaybackServerNetworkBaseline.Result(
            byteCount: 4 * 1_024 * 1_024,
            elapsedSeconds: 0.42,
            observedBitrate: 79_000_000,
            createdAt: Date(timeIntervalSince1970: 100),
            serverKey: "https://example.com",
            networkScope: "default"
        )

        let decision = DirectPlayStartupPolicy.decision(
            route: .directPlay(URL(string: "https://example.com/Videos/item/stream.mp4?static=true")!),
            sourceBitrate: 21_868_794,
            itemPreheatResult: nil,
            serverBaselineResult: baseline,
            isTVOS: true,
            now: Date(timeIntervalSince1970: 120)
        )

        XCTAssertEqual(decision.mode, .fast)
        XCTAssertEqual(decision.minimumBufferDuration, 0)
        XCTAssertNil(decision.failureReason)
    }

    func testHighBitrateDirectPlayFallsBackToGuardedModeWhenServerBaselineIsStale() {
        let baseline = PlaybackServerNetworkBaseline.Result(
            byteCount: 4 * 1_024 * 1_024,
            elapsedSeconds: 0.42,
            observedBitrate: 79_000_000,
            createdAt: Date(timeIntervalSince1970: 10),
            serverKey: "https://example.com",
            networkScope: "default"
        )

        let decision = DirectPlayStartupPolicy.decision(
            route: .directPlay(URL(string: "https://example.com/Videos/item/stream.mp4?static=true")!),
            sourceBitrate: 21_868_794,
            itemPreheatResult: nil,
            serverBaselineResult: baseline,
            isTVOS: false,
            now: Date(timeIntervalSince1970: 120)
        )

        XCTAssertEqual(decision.mode, .guarded)
        XCTAssertNil(decision.failureReason)
    }

    func testHighBitrateDirectPlayUsesGuardedModeWhenOnlyServerBaselineIsUsable() {
        let baseline = PlaybackServerNetworkBaseline.Result(
            byteCount: 4 * 1_024 * 1_024,
            elapsedSeconds: 1.15,
            observedBitrate: 30_000_000,
            createdAt: Date(timeIntervalSince1970: 100),
            serverKey: "https://example.com",
            networkScope: "default"
        )

        let decision = DirectPlayStartupPolicy.decision(
            route: .directPlay(URL(string: "https://example.com/Videos/item/stream.mp4?static=true")!),
            sourceBitrate: 21_868_794,
            itemPreheatResult: nil,
            serverBaselineResult: baseline,
            isTVOS: false,
            now: Date(timeIntervalSince1970: 120)
        )

        XCTAssertEqual(decision.mode, .guarded)
        XCTAssertNil(decision.failureReason)
    }

    func testItemPreheatOverridesHealthyServerBaseline() {
        let preheat = PlaybackStartupPreheater.Result(
            byteCount: 2 * 1_024 * 1_024,
            elapsedSeconds: 2.5,
            observedBitrate: 12_000_000,
            rangeStart: 2_048,
            reason: "directplay_range_deep"
        )
        let baseline = PlaybackServerNetworkBaseline.Result(
            byteCount: 4 * 1_024 * 1_024,
            elapsedSeconds: 0.3,
            observedBitrate: 110_000_000,
            createdAt: Date(timeIntervalSince1970: 100),
            serverKey: "https://example.com",
            networkScope: "default"
        )

        let decision = DirectPlayStartupPolicy.decision(
            route: .directPlay(URL(string: "https://example.com/Videos/item/stream.mp4?static=true")!),
            sourceBitrate: 21_868_794,
            itemPreheatResult: preheat,
            serverBaselineResult: baseline,
            isTVOS: false,
            now: Date(timeIntervalSince1970: 120)
        )

        XCTAssertEqual(decision.mode, .blocked)
        XCTAssertEqual(decision.failureReason, .directPlayPreflightInsufficient)
    }

    func testIPhoneHighBitrateDirectPlayUsesGuardedModeEvenWhenPreheatHasClearHeadroom() {
        let preheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.2,
            observedBitrate: 84_000_000,
            rangeStart: 2_048,
            reason: "directplay_range_deep"
        )

        let decision = DirectPlayStartupPolicy.decision(
            route: .directPlay(URL(string: "https://example.com/Videos/item/stream.mp4?static=true")!),
            sourceBitrate: 21_868_794,
            preheatResult: preheat,
            isTVOS: false
        )

        XCTAssertEqual(decision.mode, .guarded)
        XCTAssertEqual(decision.minimumBufferDuration, 20)
        XCTAssertEqual(decision.preferredBufferDuration, 30)
        XCTAssertEqual(decision.timeout, 45)
        XCTAssertFalse(decision.allowsTimeoutStart)
        XCTAssertNil(decision.failureReason)
    }

    func testTvOSHighBitrateDirectPlayCanUseFastModeWhenPreheatHasClearHeadroom() {
        let preheat = PlaybackStartupPreheater.Result(
            byteCount: 12 * 1_024 * 1_024,
            elapsedSeconds: 1.2,
            observedBitrate: 84_000_000,
            rangeStart: 2_048,
            reason: "directplay_range_deep"
        )

        let decision = DirectPlayStartupPolicy.decision(
            route: .directPlay(URL(string: "https://example.com/Videos/item/stream.mp4?static=true")!),
            sourceBitrate: 21_868_794,
            preheatResult: preheat,
            isTVOS: true
        )

        XCTAssertEqual(decision.mode, .fast)
        XCTAssertEqual(decision.minimumBufferDuration, 0)
        XCTAssertEqual(decision.preferredBufferDuration, 0)
        XCTAssertEqual(decision.timeout, 3)
        XCTAssertTrue(decision.allowsTimeoutStart)
        XCTAssertNil(decision.failureReason)
    }

    func testHighBitrateDirectPlayUsesGuardedModeWhenPreheatIsUsableButNotFast() {
        let preheat = PlaybackStartupPreheater.Result(
            byteCount: 8 * 1_024 * 1_024,
            elapsedSeconds: 2.4,
            observedBitrate: 28_000_000,
            rangeStart: 2_048,
            reason: "directplay_range_deep"
        )

        let decision = DirectPlayStartupPolicy.decision(
            route: .directPlay(URL(string: "https://example.com/Videos/item/stream.mp4?static=true")!),
            sourceBitrate: 21_868_794,
            preheatResult: preheat,
            isTVOS: false
        )

        XCTAssertEqual(decision.mode, .guarded)
        XCTAssertEqual(decision.minimumBufferDuration, 20)
        XCTAssertEqual(decision.preferredBufferDuration, 30)
        XCTAssertEqual(decision.timeout, 45)
        XCTAssertFalse(decision.allowsTimeoutStart)
        XCTAssertNil(decision.failureReason)
    }

    func testHighBitrateDirectPlayBlocksOnlyWhenPreheatShowsBadHeadroom() {
        let preheat = PlaybackStartupPreheater.Result(
            byteCount: 2 * 1_024 * 1_024,
            elapsedSeconds: 2.5,
            observedBitrate: 12_000_000,
            rangeStart: 2_048,
            reason: "directplay_range_deep"
        )

        let decision = DirectPlayStartupPolicy.decision(
            route: .directPlay(URL(string: "https://example.com/Videos/item/stream.mp4?static=true")!),
            sourceBitrate: 21_868_794,
            preheatResult: preheat,
            isTVOS: false
        )

        XCTAssertEqual(decision.mode, .blocked)
        XCTAssertEqual(decision.failureReason, .directPlayPreflightInsufficient)
    }

    func testLowBitrateDirectPlayUsesFastModeWithoutPreheat() {
        let decision = DirectPlayStartupPolicy.decision(
            route: .directPlay(URL(string: "https://example.com/Videos/item/stream.mp4?static=true")!),
            sourceBitrate: 8_000_000,
            preheatResult: nil,
            isTVOS: false
        )

        XCTAssertEqual(decision.mode, .fast)
        XCTAssertNil(decision.failureReason)
    }

    func testLowBitrateHDRDolbyVisionDirectPlayUsesGuardedModeWithoutPreheat() {
        let decision = DirectPlayStartupPolicy.decision(
            route: .directPlay(URL(string: "https://example.com/Videos/item/stream.mp4?static=true")!),
            sourceBitrate: 7_947_759,
            sourceIsHDRorDV: true,
            preheatResult: nil,
            isTVOS: false
        )

        XCTAssertEqual(decision.mode, .guarded)
        XCTAssertEqual(decision.minimumBufferDuration, 20)
        XCTAssertEqual(decision.preferredBufferDuration, 30)
        XCTAssertEqual(decision.timeout, 45)
        XCTAssertFalse(decision.allowsTimeoutStart)
        XCTAssertNil(decision.failureReason)
    }

    func testHighBitrateDirectPlayUsesGuardedModeWithoutMeasuredEvidence() {
        let decision = DirectPlayStartupPolicy.decision(
            route: .directPlay(URL(string: "https://example.com/Videos/item/stream.mp4?static=true")!),
            sourceBitrate: 21_868_794,
            itemPreheatResult: nil,
            serverBaselineResult: nil,
            isTVOS: false,
            now: Date(timeIntervalSince1970: 120)
        )

        XCTAssertEqual(decision.mode, .guarded)
        XCTAssertEqual(decision.minimumBufferDuration, 20)
        XCTAssertEqual(decision.preferredBufferDuration, 30)
        XCTAssertEqual(decision.timeout, 45)
        XCTAssertFalse(decision.allowsTimeoutStart)
        XCTAssertNil(decision.failureReason)
    }
}
