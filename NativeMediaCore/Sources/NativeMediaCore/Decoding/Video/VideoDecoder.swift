import CoreMedia
import CoreVideo
import Foundation

public struct DecodedVideoFrame: @unchecked Sendable {
    public var pixelBuffer: CVPixelBuffer?
    public var sampleBuffer: CMSampleBuffer?
    public var presentationTime: CMTime
    public var duration: CMTime?
    public var hdrMetadata: HDRMetadata?

    public init(
        pixelBuffer: CVPixelBuffer? = nil,
        sampleBuffer: CMSampleBuffer? = nil,
        presentationTime: CMTime,
        duration: CMTime? = nil,
        hdrMetadata: HDRMetadata? = nil
    ) {
        self.pixelBuffer = pixelBuffer
        self.sampleBuffer = sampleBuffer
        self.presentationTime = presentationTime
        self.duration = duration
        self.hdrMetadata = hdrMetadata
    }
}

public struct VideoDecodeDiagnostics: Equatable, Sendable {
    public var codec: String
    public var profile: String?
    public var level: String?
    public var hardwareDecodeActive: Bool
    public var softwareDecodeActive: Bool
    public var decodedFrames: Int
    public var droppedFrames: Int
    public var decodeLatencyMs: Double
    public var frameQueueDepth: Int

    public init(codec: String = "unknown") {
        self.codec = codec
        self.hardwareDecodeActive = false
        self.softwareDecodeActive = false
        self.decodedFrames = 0
        self.droppedFrames = 0
        self.decodeLatencyMs = 0
        self.frameQueueDepth = 0
    }
}

public protocol VideoDecoder: Sendable {
    func configure(track: MediaTrack) async throws
    func decode(packet: MediaPacket) async throws -> DecodedVideoFrame?
    func flush() async
    func diagnostics() async -> VideoDecodeDiagnostics
}

public protocol SoftwareVideoDecoder: VideoDecoder {}
