import Foundation

public struct VideoDecoderFactory: Sendable {
    public var preferAppleHardwareDecode: Bool
    public var allowSoftwareDecode: Bool

    public init(preferAppleHardwareDecode: Bool = true, allowSoftwareDecode: Bool = true) {
        self.preferAppleHardwareDecode = preferAppleHardwareDecode
        self.allowSoftwareDecode = allowSoftwareDecode
    }

    public func makeDecoder(for track: MediaTrack) throws -> any VideoDecoder {
        if preferAppleHardwareDecode, ["h264", "avc1", "hevc", "h265", "hvc1", "hev1"].contains(track.codec.lowercased()) {
            return VideoToolboxDecoder()
        }
        if allowSoftwareDecode {
            return MissingSoftwareVideoDecoder(codec: track.codec)
        }
        throw FallbackReason.decoderBackendMissing(codec: track.codec)
    }
}

public actor MissingSoftwareVideoDecoder: SoftwareVideoDecoder {
    private let codec: String

    public init(codec: String) {
        self.codec = codec
    }

    public func configure(track: MediaTrack) async throws {
        throw FallbackReason.decoderBackendMissing(codec: track.codec)
    }

    public func decode(packet: MediaPacket) async throws -> DecodedVideoFrame? {
        _ = packet
        throw FallbackReason.decoderBackendMissing(codec: codec)
    }

    public func flush() async {}

    public func diagnostics() async -> VideoDecodeDiagnostics {
        VideoDecodeDiagnostics(codec: codec)
    }
}
