@preconcurrency import AVFoundation
import CoreMedia
import Foundation

public struct AudioFormatDescriptor: Hashable, Sendable {
    public var codec: String
    public var sampleRate: Double?
    public var channels: Int?
    public var channelLayout: String?
    public var bitrate: Int?

    public init(codec: String, sampleRate: Double? = nil, channels: Int? = nil, channelLayout: String? = nil, bitrate: Int? = nil) {
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.channelLayout = channelLayout
        self.bitrate = bitrate
    }
}

public struct DecodedAudioFrame: @unchecked Sendable {
    public var pcmBuffer: AVAudioPCMBuffer?
    public var sampleBuffer: CMSampleBuffer?
    public var presentationTime: CMTime
    public var duration: CMTime?

    public init(
        pcmBuffer: AVAudioPCMBuffer? = nil,
        sampleBuffer: CMSampleBuffer? = nil,
        presentationTime: CMTime,
        duration: CMTime? = nil
    ) {
        self.pcmBuffer = pcmBuffer
        self.sampleBuffer = sampleBuffer
        self.presentationTime = presentationTime
        self.duration = duration
    }
}

public struct AudioDecodeDiagnostics: Equatable, Sendable {
    public var codec: String
    public var decoderBackend: String
    public var sampleRate: Double?
    public var channels: Int?
    public var channelLayout: String?
    public var bitrate: Int?
    public var passthroughActive: Bool
    public var bufferUnderruns: Int

    public init(codec: String = "unknown", decoderBackend: String = "unknown") {
        self.codec = codec
        self.decoderBackend = decoderBackend
        self.passthroughActive = false
        self.bufferUnderruns = 0
    }
}

public protocol AudioDecoder: Sendable {
    func configure(track: MediaTrack) async throws
    func decode(packet: MediaPacket) async throws -> DecodedAudioFrame?
    func diagnostics() async -> AudioDecodeDiagnostics
}

public protocol SoftwareAudioDecoder: AudioDecoder {}
