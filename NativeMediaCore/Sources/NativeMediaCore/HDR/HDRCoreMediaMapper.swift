import CoreMedia
import Foundation

public enum HDRCoreMediaMapper {
    public static func formatDescriptionExtensions(for metadata: HDRMetadata?) -> CFDictionary? {
        guard let metadata else { return nil }
        var extensions: [CFString: Any] = [:]

        if let value = colorPrimaries(for: metadata) {
            extensions[kCMFormatDescriptionExtension_ColorPrimaries] = value
        }
        if let value = transferFunction(for: metadata) {
            extensions[kCMFormatDescriptionExtension_TransferFunction] = value
        }
        if let value = yCbCrMatrix(for: metadata) {
            extensions[kCMFormatDescriptionExtension_YCbCrMatrix] = value
        }
        if let bitDepth = metadata.bitDepth, bitDepth > 0 {
            extensions[kCMFormatDescriptionExtension_Depth] = NSNumber(value: bitDepth)
        }

        return extensions.isEmpty ? nil : extensions as CFDictionary
    }

    public static func metadata(
        from formatDescription: CMFormatDescription?,
        codecFourCC: String? = nil,
        fallbackBitDepth: Int? = nil
    ) -> HDRMetadata? {
        let normalizedCodec = codecFourCC?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isDolbyVision = normalizedCodec == "dvh1" || normalizedCodec == "dvhe"
        guard
            let formatDescription,
            let extensions = CMFormatDescriptionGetExtensions(formatDescription) as NSDictionary?
        else {
            return isDolbyVision
                ? HDRMetadata(format: .dolbyVision, bitDepth: fallbackBitDepth, dolbyVision: DolbyVisionMetadata(source: "codecFourCC"))
                : nil
        }

        let primaries = colorPrimaries(from: extensions[kCMFormatDescriptionExtension_ColorPrimaries])
        let transfer = transferFunction(from: extensions[kCMFormatDescriptionExtension_TransferFunction])
        let matrix = yCbCrMatrix(from: extensions[kCMFormatDescriptionExtension_YCbCrMatrix])
        let bitDepth = (extensions[kCMFormatDescriptionExtension_Depth] as? NSNumber).map(\.intValue) ?? fallbackBitDepth
        let format = inferredFormat(isDolbyVision: isDolbyVision, transfer: transfer)
        let hasUsefulMetadata = format != .unknown
            || primaries != .unknown
            || transfer != .unknown
            || matrix != .unknown
            || bitDepth != nil
        guard hasUsefulMetadata else { return nil }

        return HDRMetadata(
            format: format,
            colorPrimaries: primaries,
            transferFunction: transfer,
            matrixCoefficients: matrix,
            bitDepth: bitDepth,
            dolbyVision: isDolbyVision ? DolbyVisionMetadata(source: "cmFormatDescription") : nil
        )
    }

    private static func inferredFormat(isDolbyVision: Bool, transfer: TransferFunction) -> HDRFormat {
        if isDolbyVision { return .dolbyVision }
        switch transfer {
        case .pq: return .hdr10
        case .hlg: return .hlg
        case .sdr: return .sdr
        case .unknown: return .unknown
        }
    }

    private static func colorPrimaries(for metadata: HDRMetadata) -> CFString? {
        switch effectiveColorPrimaries(metadata) {
        case .bt2020: return kCMFormatDescriptionColorPrimaries_ITU_R_2020
        case .bt709: return kCMFormatDescriptionColorPrimaries_ITU_R_709_2
        case .displayP3: return kCMFormatDescriptionColorPrimaries_P3_D65
        case .unknown: return nil
        }
    }

    private static func transferFunction(for metadata: HDRMetadata) -> CFString? {
        switch effectiveTransferFunction(metadata) {
        case .pq: return kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
        case .hlg: return kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG
        case .sdr: return kCMFormatDescriptionTransferFunction_ITU_R_709_2
        case .unknown: return nil
        }
    }

    private static func yCbCrMatrix(for metadata: HDRMetadata) -> CFString? {
        switch effectiveMatrix(metadata) {
        case .bt2020Constant, .bt2020NonConstant: return kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
        case .bt709: return kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2
        case .unknown: return nil
        }
    }

    private static func effectiveColorPrimaries(_ metadata: HDRMetadata) -> ColorPrimaries {
        if metadata.colorPrimaries != .unknown { return metadata.colorPrimaries }
        switch metadata.format {
        case .hdr10, .hdr10Plus, .hlg, .dolbyVision:
            return .bt2020
        case .sdr:
            return .bt709
        case .unknown:
            return .unknown
        }
    }

    private static func effectiveTransferFunction(_ metadata: HDRMetadata) -> TransferFunction {
        if metadata.transferFunction != .unknown { return metadata.transferFunction }
        switch metadata.format {
        case .hdr10, .hdr10Plus, .dolbyVision:
            return .pq
        case .hlg:
            return .hlg
        case .sdr:
            return .sdr
        case .unknown:
            return .unknown
        }
    }

    private static func effectiveMatrix(_ metadata: HDRMetadata) -> MatrixCoefficients {
        if metadata.matrixCoefficients != .unknown { return metadata.matrixCoefficients }
        switch metadata.format {
        case .hdr10, .hdr10Plus, .hlg, .dolbyVision:
            return .bt2020NonConstant
        case .sdr:
            return .bt709
        case .unknown:
            return .unknown
        }
    }

    private static func colorPrimaries(from rawValue: Any?) -> ColorPrimaries {
        guard let value = stringValue(rawValue) else { return .unknown }
        if value == kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String {
            return .bt2020
        }
        if value == kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String {
            return .bt709
        }
        if value == kCMFormatDescriptionColorPrimaries_P3_D65 as String
            || value == kCMFormatDescriptionColorPrimaries_DCI_P3 as String {
            return .displayP3
        }
        return .unknown
    }

    private static func transferFunction(from rawValue: Any?) -> TransferFunction {
        guard let value = stringValue(rawValue) else { return .unknown }
        if value == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String {
            return .pq
        }
        if value == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String {
            return .hlg
        }
        if value == kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String
            || value == kCMFormatDescriptionTransferFunction_sRGB as String {
            return .sdr
        }
        return .unknown
    }

    private static func yCbCrMatrix(from rawValue: Any?) -> MatrixCoefficients {
        guard let value = stringValue(rawValue) else { return .unknown }
        if value == kCMFormatDescriptionYCbCrMatrix_ITU_R_2020 as String {
            return .bt2020NonConstant
        }
        if value == kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String {
            return .bt709
        }
        return .unknown
    }

    private static func stringValue(_ rawValue: Any?) -> String? {
        guard let rawValue else { return nil }
        if let value = rawValue as? String { return value }
        return String(describing: rawValue)
    }
}
