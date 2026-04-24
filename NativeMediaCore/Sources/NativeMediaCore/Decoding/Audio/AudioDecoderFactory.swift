import Foundation

public struct AudioDecoderFactory: Sendable {
    public init() {}

    public func makeDecoder(for track: MediaTrack) throws -> any AudioDecoder {
        let codec = track.codec.lowercased()
        if ["aac", "mp3", "alac", "ac3", "eac3", "flac", "opus", "pcm"].contains(codec) {
            return AppleAudioDecoder()
        }
        return MissingSoftwareAudioDecoder(codec: codec)
    }
}

public actor AppleAudioDecoder: AudioDecoder {
    private var snapshot = AudioDecodeDiagnostics(decoderBackend: "AppleAudioToolbox")
    private var sampleBuilder: CompressedAudioSampleBuilder?

    public init() {}

    public func configure(track: MediaTrack) async throws {
        snapshot.codec = track.codec
        snapshot.bitrate = track.bitrate
        snapshot.sampleRate = track.audioSampleRate
        snapshot.channels = track.audioChannels
        snapshot.channelLayout = ChannelLayoutMapper.layoutName(channels: track.audioChannels)
        sampleBuilder = try CompressedAudioSampleBuilder(track: track)
    }

    public func decode(packet: MediaPacket) async throws -> DecodedAudioFrame? {
        guard let sampleBuilder else {
            throw FallbackReason.decoderBackendMissing(codec: "AppleAudioDecoder not configured")
        }
        return DecodedAudioFrame(
            sampleBuffer: try sampleBuilder.makeSampleBuffer(packet: packet),
            presentationTime: packet.timestamp.pts,
            duration: packet.timestamp.duration
        )
    }

    public func diagnostics() async -> AudioDecodeDiagnostics {
        snapshot
    }
}

public actor MissingSoftwareAudioDecoder: SoftwareAudioDecoder {
    private let codec: String

    public init(codec: String) {
        self.codec = codec
    }

    public func configure(track: MediaTrack) async throws {
        throw FallbackReason.decoderBackendMissing(codec: track.codec)
    }

    public func decode(packet: MediaPacket) async throws -> DecodedAudioFrame? {
        _ = packet
        throw FallbackReason.decoderBackendMissing(codec: codec)
    }

    public func diagnostics() async -> AudioDecodeDiagnostics {
        AudioDecodeDiagnostics(codec: codec, decoderBackend: "missing-software-backend")
    }
}

public enum ChannelLayoutMapper {
    public static func layoutName(channels: Int?) -> String? {
        switch channels {
        case 1: return "mono"
        case 2: return "stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return channels.map { "\($0)ch" }
        }
    }
}
