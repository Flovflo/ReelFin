import AudioToolbox
import CoreMedia
import Foundation

public enum AudioFormatDescriptionFactory {
    public static func make(track: MediaTrack) throws -> CMAudioFormatDescription {
        var description: CMAudioFormatDescription?
        var asbd = try streamDescription(for: track)
        let cookie = magicCookie(for: track)
        let status = cookie.withUnsafeBytes { bytes in
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &asbd,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: cookie.count,
                magicCookie: bytes.baseAddress,
                extensions: nil,
                formatDescriptionOut: &description
            )
        }
        guard status == noErr, let description else {
            throw FallbackReason.decoderBackendMissing(codec: "\(track.codec): audio format description status \(status)")
        }
        return description
    }

    private static func streamDescription(for track: MediaTrack) throws -> AudioStreamBasicDescription {
        let codec = track.codec.lowercased()
        let config = AACAudioSpecificConfig(data: track.codecPrivateData)
        let opus = OpusHeadConfig(data: track.codecPrivateData)
        let sampleRate = track.audioSampleRate ?? config?.sampleRate ?? opus?.sampleRate ?? defaultSampleRate(for: codec)
        let channels = track.audioChannels ?? config?.channels ?? opus?.channels ?? defaultChannels(for: codec)
        guard let sampleRate, let channels else {
            throw FallbackReason.decoderBackendMissing(codec: "\(track.codec): missing sample rate or channel count")
        }
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: try formatID(for: codec),
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: framesPerPacket(for: codec),
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: UInt32(track.audioBitDepth ?? 0),
            mReserved: 0
        )
    }

    private static func formatID(for codec: String) throws -> AudioFormatID {
        switch codec {
        case "aac": return kAudioFormatMPEG4AAC
        case "ac3": return kAudioFormatAC3
        case "eac3": return kAudioFormatEnhancedAC3
        case "mp3": return kAudioFormatMPEGLayer3
        case "alac": return kAudioFormatAppleLossless
        case "flac": return kAudioFormatFLAC
        case "opus": return kAudioFormatOpus
        case "pcm": return kAudioFormatLinearPCM
        default: throw FallbackReason.decoderBackendMissing(codec: codec)
        }
    }

    private static func framesPerPacket(for codec: String) -> UInt32 {
        switch codec {
        case "aac", "alac": return 1024
        case "ac3", "eac3": return 1536
        case "mp3": return 1152
        case "opus", "flac": return 0
        default: return 1
        }
    }

    private static func magicCookie(for track: MediaTrack) -> Data {
        if let privateData = track.codecPrivateData, !privateData.isEmpty {
            return privateData
        }
        guard track.codec.lowercased() == "aac" else { return Data() }
        return AACAudioSpecificConfig.makeAACLC(
            sampleRate: track.audioSampleRate,
            channels: track.audioChannels
        ) ?? Data()
    }

    private static func defaultSampleRate(for codec: String) -> Double? {
        codec == "opus" ? 48_000 : nil
    }

    private static func defaultChannels(for codec: String) -> Int? {
        codec == "pcm" ? 2 : nil
    }
}

public struct AACAudioSpecificConfig: Equatable, Sendable {
    public var audioObjectType: Int
    public var sampleRate: Double?
    public var channels: Int?

    public init?(data: Data?) {
        guard let data, data.count >= 2 else { return nil }
        let first = data[data.startIndex]
        let second = data[data.index(after: data.startIndex)]
        audioObjectType = Int(first >> 3)
        let sampleRateIndex = Int(((first & 0x07) << 1) | (second >> 7))
        sampleRate = Self.sampleRates[safe: sampleRateIndex].map(Double.init)
        channels = Int((second >> 3) & 0x0F)
    }

    public static func makeAACLC(sampleRate: Double?, channels: Int?) -> Data? {
        guard
            let sampleRate,
            let channels,
            let index = sampleRates.firstIndex(of: Int(sampleRate.rounded()))
        else { return nil }
        let objectType = 2
        return Data([
            UInt8((objectType << 3) | ((index & 0x0E) >> 1)),
            UInt8(((index & 0x01) << 7) | ((channels & 0x0F) << 3))
        ])
    }

    private static let sampleRates = [
        96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000,
        22_050, 16_000, 12_000, 11_025, 8_000, 7_350
    ]
}

public struct OpusHeadConfig: Equatable, Sendable {
    public var channels: Int
    public var sampleRate: Double

    public init?(data: Data?) {
        guard let data, data.count >= 19 else { return nil }
        guard String(data: data.prefix(8), encoding: .ascii) == "OpusHead" else { return nil }
        channels = Int(data[data.index(data.startIndex, offsetBy: 9)])
        let offset = data.index(data.startIndex, offsetBy: 12)
        let rawRate = UInt32(data[offset])
            | (UInt32(data[data.index(offset, offsetBy: 1)]) << 8)
            | (UInt32(data[data.index(offset, offsetBy: 2)]) << 16)
            | (UInt32(data[data.index(offset, offsetBy: 3)]) << 24)
        sampleRate = rawRate == 0 ? 48_000 : Double(rawRate)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
