import CoreMedia
import Foundation

public enum VideoFormatDescriptionFactory {
    public static func make(track: MediaTrack) throws -> CMVideoFormatDescription {
        switch track.codec.lowercased() {
        case "h264", "avc1":
            return try makeH264Description(privateData: track.codecPrivateData)
        case "hevc", "h265", "hvc1", "hev1":
            return try makeHEVCDescription(privateData: track.codecPrivateData, hdrMetadata: track.hdrMetadata)
        default:
            throw FallbackReason.decoderBackendMissing(codec: track.codec)
        }
    }

    public static func makeH264Description(config: AVCDecoderConfiguration) throws -> CMVideoFormatDescription {
        let parameterSets = config.sps + config.pps
        guard !parameterSets.isEmpty else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(codecPrivateReason: "avcC has no parameter sets")
        }
        var description: CMFormatDescription?
        let status = withParameterSetPointers(parameterSets) { pointers, sizes in
            CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: parameterSets.count,
                parameterSetPointers: pointers,
                parameterSetSizes: sizes,
                nalUnitHeaderLength: Int32(config.nalUnitLengthSize),
                formatDescriptionOut: &description
            )
        }
        guard status == noErr, let typed = description else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(
                codecPrivateReason: "CMVideoFormatDescription status \(status)"
            )
        }
        return typed
    }

    public static func makeHEVCDescription(
        config: HEVCDecoderConfiguration,
        hdrMetadata: HDRMetadata? = nil
    ) throws -> CMVideoFormatDescription {
        let parameterSets = config.vps + config.sps + config.pps
        guard !parameterSets.isEmpty else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(codecPrivateReason: "hvcC has no VPS/SPS/PPS")
        }
        var description: CMFormatDescription?
        let status = withParameterSetPointers(parameterSets) { pointers, sizes in
            CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: parameterSets.count,
                parameterSetPointers: pointers,
                parameterSetSizes: sizes,
                nalUnitHeaderLength: Int32(config.nalUnitLengthSize),
                extensions: HDRCoreMediaMapper.formatDescriptionExtensions(for: hdrMetadata),
                formatDescriptionOut: &description
            )
        }
        guard status == noErr, let typed = description else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(
                codecPrivateReason: "HEVC CMVideoFormatDescription status \(status)"
            )
        }
        return typed
    }

    private static func makeH264Description(privateData: Data?) throws -> CMVideoFormatDescription {
        guard let privateData else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(codecPrivateReason: "missing avcC")
        }
        let config = try VideoCodecPrivateDataParser.parseAVCDecoderConfigurationRecord(privateData)
        return try makeH264Description(config: config)
    }

    private static func makeHEVCDescription(privateData: Data?, hdrMetadata: HDRMetadata?) throws -> CMVideoFormatDescription {
        guard let privateData else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(codecPrivateReason: "missing hvcC")
        }
        let config = try VideoCodecPrivateDataParser.parseHEVCDecoderConfigurationRecord(privateData)
        return try makeHEVCDescription(config: config, hdrMetadata: hdrMetadata)
    }
}

func withParameterSetPointers<T>(
    _ parameterSets: [Data],
    _ body: ([UnsafePointer<UInt8>], [Int]) -> T
) -> T {
    var pointers: [UnsafePointer<UInt8>] = []
    var sizes: [Int] = []

    func recurse(_ index: Int) -> T {
        guard index < parameterSets.count else {
            return body(pointers, sizes)
        }
        return parameterSets[index].withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return recurse(index + 1)
            }
            pointers.append(baseAddress)
            sizes.append(parameterSets[index].count)
            defer {
                pointers.removeLast()
                sizes.removeLast()
            }
            return recurse(index + 1)
        }
    }

    return recurse(0)
}
