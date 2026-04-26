import CoreMedia
import Foundation

public struct CompressedVideoSampleBuilder: @unchecked Sendable {
    private let formatDescription: CMVideoFormatDescription
    private let nalUnitLengthSize: Int?

    public init(track: MediaTrack) throws {
        switch track.codec.lowercased() {
        case "h264", "avc1":
            guard let privateData = track.codecPrivateData else {
                throw FallbackReason.videoToolboxFormatDescriptionFailed(codecPrivateReason: "missing avcC")
            }
            let config = try VideoCodecPrivateDataParser.parseAVCDecoderConfigurationRecord(privateData)
            self.formatDescription = try VideoFormatDescriptionFactory.makeH264Description(config: config)
            self.nalUnitLengthSize = config.nalUnitLengthSize
        case "hevc", "h265", "hvc1", "hev1":
            guard let privateData = track.codecPrivateData else {
                throw FallbackReason.videoToolboxFormatDescriptionFailed(codecPrivateReason: "missing hvcC")
            }
            let config = try VideoCodecPrivateDataParser.parseHEVCDecoderConfigurationRecord(privateData)
            self.formatDescription = try VideoFormatDescriptionFactory.makeHEVCDescription(
                config: config,
                hdrMetadata: track.hdrMetadata
            )
            self.nalUnitLengthSize = config.nalUnitLengthSize
        default:
            self.formatDescription = try VideoFormatDescriptionFactory.make(track: track)
            self.nalUnitLengthSize = nil
        }
    }

    public init(formatDescription: CMVideoFormatDescription) {
        self.formatDescription = formatDescription
        self.nalUnitLengthSize = nil
    }

    public func makeSampleBuffer(packet: MediaPacket) throws -> CMSampleBuffer {
        let packetData = try VideoPacketNormalizer.normalizeLengthPrefixedNALUnits(
            packet.data,
            nalUnitLengthSize: nalUnitLengthSize
        )
        guard !packetData.isEmpty else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(codecPrivateReason: "empty compressed video packet")
        }
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: packetData.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: packetData.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(
                codecPrivateReason: "CMBlockBufferCreateWithMemoryBlock status \(status)"
            )
        }
        status = packetData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return OSStatus(-50) }
            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: packetData.count
            )
        }
        guard status == noErr else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(
                codecPrivateReason: "CMBlockBufferReplaceDataBytes status \(status)"
            )
        }

        var timing = CMSampleTimingInfo(
            duration: packet.timestamp.duration ?? .invalid,
            presentationTimeStamp: packet.timestamp.pts,
            decodeTimeStamp: packet.timestamp.dts ?? .invalid
        )
        var sampleSize = packetData.count
        var sampleBuffer: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(
                codecPrivateReason: "CMSampleBufferCreateReady status \(status)"
            )
        }
        markSyncAttachment(sampleBuffer, isKeyframe: packet.isKeyframe)
        return sampleBuffer
    }
}

private func markSyncAttachment(_ sampleBuffer: CMSampleBuffer, isKeyframe: Bool) {
    guard
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
        CFArrayGetCount(attachments) > 0,
        let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary?.self)
    else { return }

    if isKeyframe {
        CFDictionaryRemoveValue(attachment, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
    } else {
        CFDictionarySetValue(
            attachment,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
    }
}
