import NativeMediaCore
import XCTest

final class NativePlaybackPlannerTests: XCTestCase {
    func testPlansMP4H264AACEndToEndNativePath() {
        let tracks = [
            MediaTrack(id: "1", trackId: 1, kind: .video, codec: "h264", codecID: "avc1"),
            MediaTrack(id: "2", trackId: 2, kind: .audio, codec: "aac", codecID: "mp4a")
        ]
        let stream = DemuxerStreamInfo(container: .mp4, tracks: tracks)
        let probe = ProbeResult(format: .mp4, confidence: .exactSignature, byteSignature: "ftyp", reason: "MP4")

        let plan = NativePlaybackPlanner().makePlan(probe: probe, stream: stream, access: MediaAccessMetrics())

        XCTAssertTrue(plan.canStartLocalPlayback)
        XCTAssertEqual(plan.demux.backend, "MP4Demuxer(AVAssetReader)")
        XCTAssertEqual(plan.video?.backend, "VideoToolbox")
        XCTAssertEqual(plan.audio?.backend, "AppleAudioToolbox")
        XCTAssertEqual(plan.diagnostics.rendererBackend, "AVSampleBufferDisplayLayer")
        XCTAssertEqual(plan.diagnostics.audioRendererBackend, "AVSampleBufferAudioRenderer")
    }

    func testRoutesMatroskaH264AACToLocalBackends() {
        let tracks = [
            MediaTrack(id: "1", trackId: 1, kind: .video, codec: "h264", codecID: "V_MPEG4/ISO/AVC"),
            MediaTrack(id: "2", trackId: 2, kind: .audio, codec: "aac", codecID: "A_AAC")
        ]
        let stream = DemuxerStreamInfo(container: .matroska, tracks: tracks)
        let probe = ProbeResult(format: .matroska, confidence: .exactSignature, byteSignature: "1A 45 DF A3", reason: "EBML")

        let plan = NativePlaybackPlanner().makePlan(probe: probe, stream: stream, access: MediaAccessMetrics())

        XCTAssertEqual(plan.demux.backend, "MatroskaDemuxer(EBML)")
        XCTAssertEqual(plan.video?.backend, "VideoToolbox")
        XCTAssertEqual(plan.audio?.backend, "AppleAudioToolbox")
        XCTAssertTrue(plan.canStartLocalPlayback)
        XCTAssertEqual(plan.diagnostics.rendererBackend, "AVSampleBufferDisplayLayer(compressed)")
        XCTAssertEqual(plan.diagnostics.audioRendererBackend, "AVSampleBufferAudioRenderer")
        XCTAssertTrue(plan.fallbackReasons.isEmpty)
    }

    func testStartsMatroskaVideoWhenAudioBackendIsMissing() {
        let tracks = [
            MediaTrack(id: "1", trackId: 1, kind: .video, codec: "h264", codecID: "V_MPEG4/ISO/AVC"),
            MediaTrack(id: "2", trackId: 2, kind: .audio, codec: "truehd", codecID: "A_TRUEHD")
        ]
        let stream = DemuxerStreamInfo(container: .matroska, tracks: tracks)
        let probe = ProbeResult(format: .matroska, confidence: .exactSignature, byteSignature: "1A 45 DF A3", reason: "EBML")

        let plan = NativePlaybackPlanner().makePlan(probe: probe, stream: stream, access: MediaAccessMetrics())

        XCTAssertTrue(plan.canStartLocalPlayback)
        XCTAssertNil(plan.diagnostics.failureReason)
        XCTAssertEqual(plan.video?.backend, "VideoToolbox")
        XCTAssertEqual(plan.audio?.backend, "software-module-planned")
        XCTAssertEqual(plan.audio?.failure, .decoderBackendMissing(codec: "truehd software decoder"))
        XCTAssertTrue(plan.fallbackReasons.contains {
            $0.localizedDescription.contains("TrueHD") || $0.localizedDescription.contains("truehd")
        })
    }

    func testReportsImageSubtitleRendererAsPacketModelOnly() {
        let tracks = [
            MediaTrack(id: "1", trackId: 1, kind: .video, codec: "h264", codecID: "V_MPEG4/ISO/AVC"),
            MediaTrack(id: "3", trackId: 3, kind: .subtitle, codec: "pgs", codecID: "S_HDMV/PGS")
        ]
        let stream = DemuxerStreamInfo(container: .matroska, tracks: tracks)
        let probe = ProbeResult(format: .matroska, confidence: .exactSignature, byteSignature: "1A 45 DF A3", reason: "EBML")

        let plan = NativePlaybackPlanner().makePlan(probe: probe, stream: stream, access: MediaAccessMetrics())

        XCTAssertTrue(plan.canStartLocalPlayback)
        XCTAssertEqual(plan.subtitle?.backend, "image-subtitle-packet-model")
        XCTAssertEqual(plan.subtitle?.failure, .decoderBackendMissing(codec: "pgs renderer"))
        XCTAssertTrue(plan.diagnostics.unsupportedModules.contains {
            $0.contains("pgs") && $0.contains("renderer")
        })
    }

    func testRoutesWebMVP9OpusAsPartialLocalPathWithAppleOpusAudio() {
        let tracks = [
            MediaTrack(id: "1", trackId: 1, kind: .video, codec: "vp9", codecID: "V_VP9"),
            MediaTrack(id: "2", trackId: 2, kind: .audio, codec: "opus", codecID: "A_OPUS")
        ]
        let stream = DemuxerStreamInfo(container: .webm, tracks: tracks)
        let probe = ProbeResult(format: .webm, confidence: .exactSignature, byteSignature: "1A 45 DF A3", reason: "EBML")

        let plan = NativePlaybackPlanner().makePlan(probe: probe, stream: stream, access: MediaAccessMetrics())

        XCTAssertEqual(plan.demux.backend, "MatroskaDemuxer(EBML)")
        XCTAssertEqual(plan.audio?.backend, "AppleAudioToolbox")
        XCTAssertEqual(plan.diagnostics.audioRendererBackend, "AVSampleBufferAudioRenderer")
        XCTAssertFalse(plan.canStartLocalPlayback)
        XCTAssertTrue(plan.fallbackReasons.contains(.decoderBackendMissing(codec: "vp9 software decoder")))
    }

    func testReportsMissingVP9SoftwareBackend() {
        let stream = DemuxerStreamInfo(
            container: .webm,
            tracks: [MediaTrack(id: "1", trackId: 1, kind: .video, codec: "vp9")]
        )
        let probe = ProbeResult(format: .webm, confidence: .hinted, byteSignature: "", reason: "hint")

        let plan = NativePlaybackPlanner().makePlan(probe: probe, stream: stream, access: MediaAccessMetrics())

        XCTAssertFalse(plan.canStartLocalPlayback)
        XCTAssertEqual(plan.video?.backend, "software-module-planned")
        XCTAssertEqual(plan.fallbackReasons.first, .decoderBackendMissing(codec: "vp9 software decoder"))
    }

    func testReportsMissingAV1SoftwareBackendInsteadOfPretendingReady() {
        let stream = DemuxerStreamInfo(
            container: .webm,
            tracks: [MediaTrack(id: "1", trackId: 1, kind: .video, codec: "av1", codecID: "V_AV1")]
        )
        let probe = ProbeResult(format: .webm, confidence: .exactSignature, byteSignature: "1A 45 DF A3", reason: "EBML")

        let plan = NativePlaybackPlanner().makePlan(probe: probe, stream: stream, access: MediaAccessMetrics())

        XCTAssertFalse(plan.canStartLocalPlayback)
        XCTAssertEqual(plan.video?.backend, "software-module-planned")
        XCTAssertEqual(plan.video?.failure, .decoderBackendMissing(codec: "av1 software decoder"))
        XCTAssertEqual(plan.diagnostics.failureReason, FallbackReason.decoderBackendMissing(codec: "av1 software decoder").localizedDescription)
    }
}
