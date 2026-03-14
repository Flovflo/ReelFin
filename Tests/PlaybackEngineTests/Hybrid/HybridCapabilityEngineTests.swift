import XCTest
@testable import PlaybackEngine
@testable import Shared

final class HybridCapabilityEngineTests: XCTestCase {
    let engine = HybridCapabilityEngine()

    // MARK: - A. Container + Codec Combinations

    func testMP4_H264_AAC_isNativePreferred() {
        let media = MediaCharacteristics(
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            supportsDirectPlay: true
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .nativePreferred)
        XCTAssertEqual(decision.startupRisk, .none)
        XCTAssertTrue(decision.reasons.contains(.containerAppleNative))
        XCTAssertTrue(decision.reasons.contains(.videoH264Native))
        XCTAssertTrue(decision.reasons.contains(.audioAACNative))
    }

    func testMP4_HEVC_AAC_isNativePreferred() {
        let media = MediaCharacteristics(
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "aac",
            supportsDirectPlay: true
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .nativePreferred)
        XCTAssertTrue(decision.reasons.contains(.videoHEVCNative))
    }

    func testMP4_HEVC_HDR10_isNativePreferred() {
        let media = MediaCharacteristics(
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitDepth: 10,
            videoRangeType: "HDR10",
            supportsDirectPlay: true
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .nativePreferred)
        XCTAssertEqual(decision.hdrExpectation, .hdr10)
        XCTAssertTrue(decision.reasons.contains(.hdrNativePreserved))
    }

    func testMP4_HEVC_DolbyVision_isNativePreferred() {
        let media = MediaCharacteristics(
            container: "mp4",
            videoCodec: "dvh1",
            audioCodec: "eac3",
            bitDepth: 10,
            videoRangeType: "DOVI",
            dvProfile: 8,
            supportsDirectPlay: true
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .nativePreferred)
        XCTAssertEqual(decision.hdrExpectation, .dolbyVision)
        XCTAssertTrue(decision.reasons.contains(.dolbyVisionNativePreserved))
    }

    // MARK: - B. VLC Required Cases

    func testMKV_PGS_requiresVLC() {
        let media = MediaCharacteristics(
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "aac",
            subtitleCodecs: ["pgs"],
            supportsDirectPlay: true
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .vlcRequired)
        XCTAssertTrue(decision.reasons.contains(.containerMKV))
        XCTAssertTrue(decision.reasons.contains(.subtitlePGSRequiresVLC))
    }

    func testMKV_DTS_requiresVLC() {
        let media = MediaCharacteristics(
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "dts",
            supportsDirectPlay: true
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .vlcRequired)
        XCTAssertTrue(decision.reasons.contains(.audioDTSRequiresVLC))
    }

    func testMKV_TrueHD_requiresVLC() {
        let media = MediaCharacteristics(
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "truehd",
            supportsDirectPlay: true
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .vlcRequired)
        XCTAssertTrue(decision.reasons.contains(.audioTrueHDRequiresVLC))
    }

    func testWebM_VP9_Opus_requiresVLC() {
        let media = MediaCharacteristics(
            container: "webm",
            videoCodec: "vp9",
            audioCodec: "opus"
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .vlcRequired)
        XCTAssertTrue(decision.reasons.contains(.containerWebM))
        XCTAssertTrue(decision.reasons.contains(.videoVP9RequiresVLC))
    }

    func testAVI_MPEG2_requiresVLC() {
        let media = MediaCharacteristics(
            container: "avi",
            videoCodec: "mpeg2",
            audioCodec: "ac3"
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .vlcRequired)
        XCTAssertTrue(decision.reasons.contains(.containerAVI))
        XCTAssertTrue(decision.reasons.contains(.videoMPEG2RequiresVLC))
    }

    func testVC1_requiresVLC() {
        let media = MediaCharacteristics(
            container: "mkv",
            videoCodec: "vc1",
            audioCodec: "ac3"
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .vlcRequired)
        XCTAssertTrue(decision.reasons.contains(.videoVC1RequiresVLC))
    }

    // MARK: - C. Missing Metadata

    func testMissingMetadata_fallsBackSafely() {
        let media = MediaCharacteristics()
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .vlcRequired)
        XCTAssertTrue(decision.reasons.contains(.metadataMissing))
        XCTAssertEqual(decision.startupRisk, .none)
    }

    // MARK: - D. Borderline Cases

    func testMP4_AV1_isNativeWithLowRisk() {
        let media = MediaCharacteristics(
            container: "mp4",
            videoCodec: "av1",
            audioCodec: "aac",
            supportsDirectPlay: true
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .nativePreferred)
    }

    func testTS_H264_isNativePreferred() {
        let media = MediaCharacteristics(
            container: "ts",
            videoCodec: "h264",
            audioCodec: "aac",
            supportsDirectPlay: true
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .nativePreferred)
    }

    func testMP4_H264_AAC_withoutDirectPlay_requiresVLC() {
        let media = MediaCharacteristics(
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            supportsDirectPlay: false,
            supportsDirectStream: true,
            hasTranscodeURL: true
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .vlcRequired)
        XCTAssertTrue(decision.reasons.contains(.fallbackToServerTranscode))
    }

    // MARK: - E. HDR Degradation When VLC Required

    func testMKV_HEVC_HDR10_DTS_degradesHDR() {
        let media = MediaCharacteristics(
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "dts",
            bitDepth: 10,
            videoRangeType: "HDR10",
            subtitleCodecs: ["pgs"]
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .vlcRequired)
        // Should note HDR degradation since VLC may not preserve it perfectly
        XCTAssertEqual(decision.hdrExpectation, .hdrDegradedByEngine)
        XCTAssertTrue(decision.reasons.contains(.hdrDegradedByVLCFallback))
    }

    // MARK: - F. Server Transcode Preferred

    func testNoDirectPlay_noDirectStream_preferTranscode() {
        let media = MediaCharacteristics(
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            hasTranscodeURL: true
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .vlcRequired)
        XCTAssertTrue(decision.reasons.contains(.fallbackToServerTranscode))
    }

    // MARK: - G. Subtitle Edge Cases

    func testMP4_H264_ASS_prefersVLCForSubtitles() {
        let media = MediaCharacteristics(
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            subtitleCodecs: ["ass"],
            supportsDirectPlay: true
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .vlcRequired)
        XCTAssertTrue(decision.reasons.contains(.subtitleASSRequiresVLC))
    }

    func testMP4_H264_VobSub_prefersVLCForSubtitles() {
        let media = MediaCharacteristics(
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            subtitleCodecs: ["vobsub"],
            supportsDirectPlay: true
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .vlcRequired)
        XCTAssertTrue(decision.reasons.contains(.subtitleVobSubRequiresVLC))
    }

    // MARK: - H. Feature Completeness

    func testNativePreferred_hasFullCompleteness() {
        let media = MediaCharacteristics(
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            supportsDirectPlay: true
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.estimatedFeatureCompleteness, 1.0)
    }

    func testVLCRequired_hasReducedCompleteness() {
        let media = MediaCharacteristics(
            container: "mkv",
            videoCodec: "vp9",
            audioCodec: "vorbis"
        )
        let decision = engine.evaluate(media)
        XCTAssertEqual(decision.recommendation, .vlcRequired)
        XCTAssertTrue(decision.estimatedFeatureCompleteness < 1.0)
    }

    // MARK: - I. Audio Codec Coverage

    func testFLAC_isNative() {
        let media = MediaCharacteristics(container: "mp4", videoCodec: "h264", audioCodec: "flac", supportsDirectPlay: true)
        let decision = engine.evaluate(media)
        XCTAssertTrue(decision.reasons.contains(.audioFLACNative))
        XCTAssertEqual(decision.recommendation, .nativePreferred)
    }

    func testALAC_isNative() {
        let media = MediaCharacteristics(container: "mp4", videoCodec: "h264", audioCodec: "alac", supportsDirectPlay: true)
        let decision = engine.evaluate(media)
        XCTAssertTrue(decision.reasons.contains(.audioALACNative))
    }

    func testEAC3_isNative() {
        let media = MediaCharacteristics(container: "mp4", videoCodec: "hevc", audioCodec: "eac3", supportsDirectPlay: true)
        let decision = engine.evaluate(media)
        XCTAssertTrue(decision.reasons.contains(.audioEAC3Native))
    }

    func testDTSHD_requiresVLC() {
        let media = MediaCharacteristics(container: "mkv", videoCodec: "hevc", audioCodec: "dts-hd")
        let decision = engine.evaluate(media)
        XCTAssertTrue(decision.reasons.contains(.audioDTSHDRequiresVLC))
        XCTAssertEqual(decision.recommendation, .vlcRequired)
    }

    func testVorbis_requiresVLC() {
        let media = MediaCharacteristics(container: "webm", videoCodec: "vp9", audioCodec: "vorbis")
        let decision = engine.evaluate(media)
        XCTAssertTrue(decision.reasons.contains(.audioVorbisRequiresVLC))
    }
}
