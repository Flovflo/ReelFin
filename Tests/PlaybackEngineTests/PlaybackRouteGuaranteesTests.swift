import PlaybackEngine
import Shared
import XCTest

final class PlaybackRouteGuaranteesTests: XCTestCase {
    func testDirectDolbyVisionMP4PreservesOriginalBitstream() {
        let source = makeGuaranteeSource(
            container: "mp4",
            videoCodec: "dvh1",
            audioCodec: "eac3",
            videoRangeType: "DOVI",
            dvProfile: 5
        )
        let url = URL(string: "https://media.example.com/video.mp4")!

        let guarantees = PlaybackRouteGuaranteeResolver.resolve(
            source: source,
            route: .directPlay(url),
            finalURL: url,
            evidence: .init()
        )

        XCTAssertEqual(guarantees.videoIntegrity, .originalBitstream)
        XCTAssertEqual(guarantees.hdrIntegrity, .dolbyVision)
        XCTAssertEqual(guarantees.startupClass, .remoteDirect)
        XCTAssertTrue(guarantees.preservesOriginalVideo)
        XCTAssertTrue(guarantees.preservesDolbyVision)
        XCTAssertFalse(guarantees.isVideoTranscode)
    }

    func testDolbyVisionMKVHLSFMP4VideoCopyIsRemuxNotVideoTranscode() {
        let source = makeGuaranteeSource(
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            videoRangeType: "DOVIWithHDR10",
            dvProfile: 8,
            dvBlSignalCompatibilityId: 1
        )
        let url = URL(string: "https://media.example.com/master.m3u8?Container=fmp4&SegmentContainer=fmp4&VideoCodec=hevc&AllowVideoStreamCopy=true&AllowAudioStreamCopy=true")!

        let guarantees = PlaybackRouteGuaranteeResolver.resolve(
            source: source,
            route: .remux(url),
            finalURL: url,
            evidence: PlaybackRouteEvidence(
                selectedVariantAllowsVideoCopy: true,
                selectedVariantIsDolbyVisionSignaled: true,
                selectedVariantIsHDRSignaled: true,
                selectedVariantUsesFMP4: true,
                initHasDvcC: true
            )
        )

        XCTAssertEqual(guarantees.videoIntegrity, .videoCopyRemux)
        XCTAssertEqual(guarantees.hdrIntegrity, .dolbyVision)
        XCTAssertEqual(guarantees.startupClass, .hlsRemux)
        XCTAssertTrue(guarantees.preservesOriginalVideo)
        XCTAssertTrue(guarantees.preservesDolbyVision)
        XCTAssertFalse(guarantees.isVideoTranscode)
    }

    func testDolbyVisionVideoTranscodeIsExplicitLoss() {
        let source = makeGuaranteeSource(
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "truehd",
            videoRangeType: "DOVI",
            dvProfile: 5
        )
        let url = URL(string: "https://media.example.com/master.m3u8?Container=ts&SegmentContainer=ts&VideoCodec=h264&AllowVideoStreamCopy=false&AllowAudioStreamCopy=false")!

        let guarantees = PlaybackRouteGuaranteeResolver.resolve(
            source: source,
            route: .transcode(url),
            finalURL: url,
            evidence: .init()
        )

        XCTAssertEqual(guarantees.videoIntegrity, .videoTranscode)
        XCTAssertEqual(guarantees.hdrIntegrity, .sdrToneMapped)
        XCTAssertEqual(guarantees.startupClass, .transcode)
        XCTAssertFalse(guarantees.preservesOriginalVideo)
        XCTAssertFalse(guarantees.preservesDolbyVision)
        XCTAssertTrue(guarantees.isVideoTranscode)
        XCTAssertTrue(guarantees.debugReason.localizedCaseInsensitiveContains("video copy disabled"))
    }

    func testDolbyVisionProfile7IsNotPromisedAsFullDolbyVisionOnRemux() {
        let source = makeGuaranteeSource(
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            videoRangeType: "DOVIWithHDR10",
            dvProfile: 7
        )
        let url = URL(string: "https://media.example.com/master.m3u8?Container=fmp4&SegmentContainer=fmp4&VideoCodec=hevc&AllowVideoStreamCopy=true")!

        let guarantees = PlaybackRouteGuaranteeResolver.resolve(
            source: source,
            route: .remux(url),
            finalURL: url,
            evidence: PlaybackRouteEvidence(
                selectedVariantAllowsVideoCopy: true,
                selectedVariantIsDolbyVisionSignaled: true,
                selectedVariantIsHDRSignaled: true,
                selectedVariantUsesFMP4: true,
                initHasDvcC: true
            )
        )

        XCTAssertEqual(guarantees.videoIntegrity, .videoCopyRemux)
        XCTAssertEqual(guarantees.hdrIntegrity, .hdr10FallbackFromDolbyVision)
        XCTAssertTrue(guarantees.preservesHDR)
        XCTAssertFalse(guarantees.preservesDolbyVision)
    }
}
