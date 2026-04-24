import NativeMediaCore
import XCTest

final class NativeDiagnosticsTests: XCTestCase {
    func testOverlayContainsOriginalAndFailureFields() {
        var diagnostics = NativePlayerDiagnostics(container: .matroska, demuxer: "MatroskaDemuxer(EBML)")
        diagnostics.playbackState = "playing"
        diagnostics.byteSourceType = "HTTPRangeByteSource"
        diagnostics.videoCodec = "hevc"
        diagnostics.videoPacketCount = 42
        diagnostics.audioCodec = "truehd"
        diagnostics.audioPacketCount = 84
        diagnostics.rendererBackend = "AVSampleBufferDisplayLayer"
        diagnostics.masterClock = "AVSampleBufferRenderSynchronizer"
        diagnostics.failureReason = FallbackReason.decoderBackendMissing(codec: "truehd").localizedDescription

        let lines = diagnostics.overlayLines.joined(separator: "\n")

        XCTAssertTrue(lines.contains("state=playing"))
        XCTAssertTrue(lines.contains("originalMediaRequested=true"))
        XCTAssertTrue(lines.contains("serverTranscodeUsed=false"))
        XCTAssertTrue(lines.contains("byteSource=HTTPRangeByteSource"))
        XCTAssertTrue(lines.contains("container=matroska"))
        XCTAssertTrue(lines.contains("packets video=42 audio=84"))
        XCTAssertTrue(lines.contains("AVSampleBufferDisplayLayer"))
        XCTAssertTrue(lines.contains("truehd"))
    }
}
