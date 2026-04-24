import CoreMedia
import Foundation

public struct CompressedAudioSampleBuilder: @unchecked Sendable {
    private let formatDescription: CMAudioFormatDescription
    private let defaultDuration: CMTime?
    private let codec: String
    private let sampleRate: Double?

    public init(track: MediaTrack) throws {
        self.formatDescription = try AudioFormatDescriptionFactory.make(track: track)
        self.defaultDuration = Self.defaultDuration(for: track)
        self.codec = track.codec.lowercased()
        self.sampleRate = track.audioSampleRate
    }

    public init(formatDescription: CMAudioFormatDescription) {
        self.formatDescription = formatDescription
        self.defaultDuration = nil
        self.codec = ""
        self.sampleRate = nil
    }

    public func makeSampleBuffer(packet: MediaPacket) throws -> CMSampleBuffer {
        guard !packet.data.isEmpty else {
            throw FallbackReason.decoderBackendMissing(codec: "empty compressed audio packet")
        }
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: packet.data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: packet.data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else {
            throw FallbackReason.decoderBackendMissing(codec: "audio CMBlockBuffer status \(status)")
        }

        status = packet.data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return OSStatus(-50) }
            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: packet.data.count
            )
        }
        guard status == noErr else {
            throw FallbackReason.decoderBackendMissing(codec: "audio block copy status \(status)")
        }

        let layout = sampleLayout(for: packet)
        var timings = layout.timings
        var sampleSizes = layout.sampleSizes
        var sampleBuffer: CMSampleBuffer?
        status = timings.withUnsafeMutableBufferPointer { timingBuffer in
            sampleSizes.withUnsafeMutableBufferPointer { sizeBuffer in
                CMSampleBufferCreateReady(
                    allocator: kCFAllocatorDefault,
                    dataBuffer: blockBuffer,
                    formatDescription: formatDescription,
                    sampleCount: layout.sampleCount,
                    sampleTimingEntryCount: timingBuffer.count,
                    sampleTimingArray: timingBuffer.baseAddress,
                    sampleSizeEntryCount: sizeBuffer.count,
                    sampleSizeArray: sizeBuffer.baseAddress,
                    sampleBufferOut: &sampleBuffer
                )
            }
        }
        guard status == noErr, let sampleBuffer else {
            throw FallbackReason.decoderBackendMissing(codec: "audio CMSampleBuffer status \(status)")
        }
        return sampleBuffer
    }

    private func sampleLayout(for packet: MediaPacket) -> CompressedAudioSampleLayout {
        if let dolby = dolbyFrames(in: packet.data), dolby.count > 1 {
            return multiFrameLayout(packet: packet, frames: dolby)
        }
        let timing = CMSampleTimingInfo(
            duration: packet.timestamp.duration ?? defaultDuration ?? .invalid,
            presentationTimeStamp: packet.timestamp.pts,
            decodeTimeStamp: packet.timestamp.dts ?? .invalid
        )
        return CompressedAudioSampleLayout(
            sampleCount: 1,
            timings: [timing],
            sampleSizes: [packet.data.count]
        )
    }

    private func multiFrameLayout(
        packet: MediaPacket,
        frames: [CompressedDolbyFrame]
    ) -> CompressedAudioSampleLayout {
        var pts = packet.timestamp.pts
        let timings = frames.map { frame in
            defer { pts = pts + frame.duration }
            return CMSampleTimingInfo(
                duration: frame.duration,
                presentationTimeStamp: pts,
                decodeTimeStamp: .invalid
            )
        }
        return CompressedAudioSampleLayout(
            sampleCount: frames.count,
            timings: timings,
            sampleSizes: frames.map(\.size)
        )
    }

    private func dolbyFrames(in data: Data) -> [CompressedDolbyFrame]? {
        guard codec == "ac3" || codec == "eac3" else { return nil }
        var offset = data.startIndex
        var frames: [CompressedDolbyFrame] = []
        while offset < data.endIndex {
            let remaining = Data(data[offset..<data.endIndex])
            guard let info = DolbyAudioHeaderParser.parse(remaining, codec: codec),
                  let frameSize = info.frameSize,
                  frameSize > 0,
                  offset + frameSize <= data.endIndex else {
                return nil
            }
            let duration = CMTime(
                value: Int64(info.sampleCount),
                timescale: CMTimeScale((sampleRate ?? info.sampleRate).rounded())
            )
            frames.append(CompressedDolbyFrame(size: frameSize, duration: duration))
            offset += frameSize
        }
        return frames.isEmpty ? nil : frames
    }

    private static func defaultDuration(for track: MediaTrack) -> CMTime? {
        guard let sampleRate = track.audioSampleRate, sampleRate > 0 else { return nil }
        let codec = track.codec.lowercased()
        let frames: Int64
        switch codec {
        case "aac", "alac":
            frames = 1024
        case "ac3", "eac3":
            frames = 1536
        case "mp3":
            frames = 1152
        default:
            return nil
        }
        return CMTime(value: frames, timescale: CMTimeScale(sampleRate.rounded()))
    }
}

private struct CompressedAudioSampleLayout {
    var sampleCount: Int
    var timings: [CMSampleTimingInfo]
    var sampleSizes: [Int]
}

private struct CompressedDolbyFrame {
    var size: Int
    var duration: CMTime
}
