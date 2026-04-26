import CoreMedia
import Foundation
import VideoToolbox

public actor VideoToolboxDecoder: VideoDecoder {
    private var track: MediaTrack?
    private var sampleBuilder: CompressedVideoSampleBuilder?
    private var snapshot = VideoDecodeDiagnostics()

    public init() {}

    public func configure(track: MediaTrack) async throws {
        self.track = track
        snapshot.codec = track.codec
        switch track.codec.lowercased() {
        case "h264", "avc1":
            sampleBuilder = try CompressedVideoSampleBuilder(track: track)
            snapshot.hardwareDecodeActive = true
        case "hevc", "h265", "hvc1", "hev1":
            sampleBuilder = try CompressedVideoSampleBuilder(track: track)
            snapshot.hardwareDecodeActive = true
        case "av1":
            throw FallbackReason.decoderBackendMissing(codec: "av1")
        default:
            throw FallbackReason.decoderBackendMissing(codec: track.codec)
        }
    }

    public func decode(packet: MediaPacket) async throws -> DecodedVideoFrame? {
        guard let sampleBuilder else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(codecPrivateReason: "decoder not configured")
        }
        let sampleBuffer = try sampleBuilder.makeSampleBuffer(packet: packet)
        snapshot.decodedFrames += 1
        snapshot.frameQueueDepth = max(0, snapshot.frameQueueDepth - 1)
        return DecodedVideoFrame(
            sampleBuffer: sampleBuffer,
            presentationTime: packet.timestamp.pts,
            duration: packet.timestamp.duration,
            hdrMetadata: track?.hdrMetadata
        )
    }

    public func flush() async {
        snapshot.frameQueueDepth = 0
    }

    public func diagnostics() async -> VideoDecodeDiagnostics {
        snapshot
    }
}
