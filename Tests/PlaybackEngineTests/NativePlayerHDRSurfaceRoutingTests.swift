import XCTest
@testable import PlaybackEngine
@testable import Shared

/// Locks the HDR/DV surface-routing boundary that the gateway/anti-stall work touched.
///
/// Root invariant (regression guard for the "10-bit == HDR" over-trigger): bit depth alone is
/// NOT an HDR signal. A 10-bit SDR (HEVC Main10) source must render on the experimental
/// sample-buffer surface (fast path) and must NOT be treated as "premium" (which would force it
/// through the stall-resistant gateway + guarded startup). Genuine HDR10 / Dolby Vision — which
/// always carry explicit range / DV signalling from Jellyfin — must be diverted to the
/// Apple-native coordinator on iOS (the sample buffer wires no EDR / DV tone-mapping → dark).
final class NativePlayerHDRSurfaceRoutingTests: XCTestCase {

    // MARK: Root predicate boundary

    func testTenBitSDRIsNotTreatedAsHDRorPremium() {
        let sdr10 = makeSource(container: "mp4", bitDepth: 10) // Main10 SDR, no range markers
        XCTAssertFalse(sdr10.hasExplicitHDRorDVSignaling, "10-bit SDR has no HDR/DV signalling")
        XCTAssertFalse(sdr10.isPremiumVideoSource, "10-bit SDR 1080p must not be premium → fast start, no gateway")
        // The broad hint still flags it (unchanged behaviour for the ~40 legacy call sites).
        XCTAssertTrue(sdr10.isLikelyHDRorDV, "broad hint intentionally still includes 10-bit")
    }

    func testEightBitSDRIsPlainSDR() {
        let sdr8 = makeSource(container: "mp4", bitDepth: 8)
        XCTAssertFalse(sdr8.hasExplicitHDRorDVSignaling)
        XCTAssertFalse(sdr8.isLikelyHDRorDV)
        XCTAssertFalse(sdr8.isPremiumVideoSource)
    }

    func testExplicitHDR10AndDolbyVisionAreSignalledAndPremium() {
        let hdr10 = makeSource(container: "mp4", bitDepth: 10, videoRange: "HDR", videoRangeType: "HDR10")
        XCTAssertTrue(hdr10.hasExplicitHDRorDVSignaling)
        XCTAssertTrue(hdr10.isPremiumVideoSource)

        let dolby = makeSource(container: "mp4", bitDepth: 10, videoRangeType: "DOVIWithHDR10", dvProfile: 8)
        XCTAssertTrue(dolby.hasExplicitHDRorDVSignaling)
        XCTAssertTrue(dolby.isPremiumVideoSource)
    }

    func test4KTenBitSDRIsPremiumViaResolutionNotHDR() {
        let uhd = makeSource(container: "mp4", bitDepth: 10, width: 3840, height: 2160)
        XCTAssertFalse(uhd.hasExplicitHDRorDVSignaling, "still SDR — no HDR signalling")
        XCTAssertTrue(uhd.isPremiumVideoSource, "4K HEVC is premium on resolution alone")
    }

    // MARK: hdrMode mapping (platform-independent)

    func testHDRModeMapping() {
        XCTAssertEqual(NativePlayerPlaybackController.hdrMode(for: makeSource(container: "mp4", bitDepth: 8)), .sdr)
        XCTAssertEqual(NativePlayerPlaybackController.hdrMode(for: makeSource(container: "mkv", bitDepth: 10)), .sdr,
                       "10-bit SDR must classify as .sdr, not .hdr10")
        XCTAssertEqual(
            NativePlayerPlaybackController.hdrMode(for: makeSource(container: "mp4", bitDepth: 10, videoRange: "HDR", videoRangeType: "HDR10")),
            .hdr10
        )
        XCTAssertEqual(
            NativePlayerPlaybackController.hdrMode(for: makeSource(container: "mp4", bitDepth: 10, videoRangeType: "DOVIWithHDR10", dvProfile: 8)),
            .dolbyVision
        )
    }

    // MARK: Sample-buffer surface reject decision

    func testSampleBufferRejectDecisionAcrossDynamicRangeAndContainer() {
        for container in ["mp4", "mkv"] {
            let sdr8 = makeSource(container: container, bitDepth: 8)
            let sdr10 = makeSource(container: container, bitDepth: 10)
            let hdr10 = makeSource(container: container, bitDepth: 10, videoRange: "HDR", videoRangeType: "HDR10")
            let dolby = makeSource(container: container, bitDepth: 10, videoRangeType: "DOVIWithHDR10", dvProfile: 8)

            #if os(tvOS)
            // tvOS drives dynamic range via AVDisplayCriteria → sample buffer is acceptable for all.
            XCTAssertFalse(NativePlayerPlaybackController.sampleBufferShouldRejectHDR(for: sdr8))
            XCTAssertFalse(NativePlayerPlaybackController.sampleBufferShouldRejectHDR(for: sdr10))
            XCTAssertFalse(NativePlayerPlaybackController.sampleBufferShouldRejectHDR(for: hdr10))
            XCTAssertFalse(NativePlayerPlaybackController.sampleBufferShouldRejectHDR(for: dolby))
            #else
            XCTAssertFalse(NativePlayerPlaybackController.sampleBufferShouldRejectHDR(for: sdr8), "\(container) SDR8 renders fine")
            XCTAssertFalse(NativePlayerPlaybackController.sampleBufferShouldRejectHDR(for: sdr10),
                           "\(container) 10-bit SDR must NOT be diverted to the coordinator")
            XCTAssertTrue(NativePlayerPlaybackController.sampleBufferShouldRejectHDR(for: hdr10),
                          "\(container) HDR10 must be diverted (no EDR on sample buffer)")
            XCTAssertTrue(NativePlayerPlaybackController.sampleBufferShouldRejectHDR(for: dolby),
                          "\(container) Dolby Vision must be diverted")
            #endif
        }
    }

    private func makeSource(
        container: String,
        bitDepth: Int,
        videoRange: String? = nil,
        videoRangeType: String? = nil,
        dvProfile: Int? = nil,
        width: Int = 1920,
        height: Int = 1080
    ) -> MediaSource {
        MediaSource(
            id: "source-1",
            itemID: "item-1",
            name: "source-1",
            filePath: "/media/movie.\(container)",
            container: container,
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 9_000_000,
            videoBitDepth: bitDepth,
            videoRange: videoRange,
            videoRangeType: videoRangeType,
            dvProfile: dvProfile,
            supportsDirectPlay: true,
            supportsDirectStream: true,
            videoWidth: width,
            videoHeight: height
        )
    }
}
