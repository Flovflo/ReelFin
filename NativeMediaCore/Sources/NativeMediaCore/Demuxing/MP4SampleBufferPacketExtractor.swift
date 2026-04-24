import CoreMedia
import CoreVideo
import Foundation

enum MP4SampleBufferPacketExtractor {
    static func packet(from sample: CMSampleBuffer, trackID: Int) throws -> MediaPacket? {
        guard let data = try sampleData(sample), !data.isEmpty else { return nil }
        return MediaPacket(
            trackID: trackID,
            timestamp: PacketTimestamp(
                pts: CMSampleBufferGetPresentationTimeStamp(sample),
                dts: optional(CMSampleBufferGetDecodeTimeStamp(sample)),
                duration: optional(CMSampleBufferGetDuration(sample))
            ),
            isKeyframe: isKeyframe(sample),
            data: data
        )
    }

    private static func sampleData(_ sample: CMSampleBuffer) throws -> Data? {
        if let imageBuffer = CMSampleBufferGetImageBuffer(sample) {
            return try pixelBufferData(imageBuffer)
        }
        guard let block = CMSampleBufferGetDataBuffer(sample) else {
            return nil
        }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        try data.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            let status = CMBlockBufferCopyDataBytes(
                block,
                atOffset: 0,
                dataLength: length,
                destination: base
            )
            guard status == kCMBlockBufferNoErr else {
                throw MP4SampleBufferPacketExtractorError.copyFailed(status)
            }
        }
        return data
    }

    private static func pixelBufferData(_ buffer: CVPixelBuffer) throws -> Data {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let planeCount = CVPixelBufferGetPlaneCount(buffer)
        guard planeCount > 0 else {
            guard let base = CVPixelBufferGetBaseAddress(buffer) else {
                throw MP4SampleBufferPacketExtractorError.missingPixelBufferBaseAddress
            }
            return Data(bytes: base, count: CVPixelBufferGetDataSize(buffer))
        }

        var data = Data()
        for plane in 0..<planeCount {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else { continue }
            let height = CVPixelBufferGetHeightOfPlane(buffer, plane)
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
            data.append(base.assumingMemoryBound(to: UInt8.self), count: height * bytesPerRow)
        }
        return data
    }

    private static func isKeyframe(_ sample: CMSampleBuffer) -> Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sample,
                createIfNecessary: false
            ) as? [[CFString: Any]],
            let first = attachments.first,
            let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool
        else {
            return true
        }
        return !notSync
    }

    private static func optional(_ time: CMTime) -> CMTime? {
        guard time.isValid && !time.isIndefinite else { return nil }
        return time
    }
}

private enum MP4SampleBufferPacketExtractorError: LocalizedError {
    case missingBlockBuffer
    case missingPixelBufferBaseAddress
    case copyFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingBlockBuffer:
            return "CMSampleBuffer does not contain compressed sample data."
        case .missingPixelBufferBaseAddress:
            return "CVPixelBuffer does not expose a readable base address."
        case .copyFailed(let status):
            return "Could not copy compressed sample data from CMSampleBuffer: \(status)."
        }
    }
}
