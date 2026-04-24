import Foundation

public enum ColorPrimaries: String, Codable, Hashable, Sendable {
    case bt709
    case bt2020
    case displayP3
    case unknown
}

public enum TransferFunction: String, Codable, Hashable, Sendable {
    case sdr
    case pq
    case hlg
    case unknown
}

public enum MatrixCoefficients: String, Codable, Hashable, Sendable {
    case bt709
    case bt2020NonConstant
    case bt2020Constant
    case unknown
}

public enum HDRFormat: String, Codable, Hashable, Sendable {
    case sdr
    case hdr10
    case hdr10Plus
    case hlg
    case dolbyVision
    case unknown
}

public struct MasteringDisplayMetadata: Codable, Hashable, Sendable {
    public var maxLuminance: Double?
    public var minLuminance: Double?

    public init(maxLuminance: Double? = nil, minLuminance: Double? = nil) {
        self.maxLuminance = maxLuminance
        self.minLuminance = minLuminance
    }
}

public struct ContentLightLevelMetadata: Codable, Hashable, Sendable {
    public var maxCLL: Int?
    public var maxFALL: Int?

    public init(maxCLL: Int? = nil, maxFALL: Int? = nil) {
        self.maxCLL = maxCLL
        self.maxFALL = maxFALL
    }
}

public struct DolbyVisionMetadata: Codable, Hashable, Sendable {
    public var profile: Int?
    public var level: Int?
    public var compatibilityID: Int?
    public var source: String

    public init(profile: Int? = nil, level: Int? = nil, compatibilityID: Int? = nil, source: String = "unknown") {
        self.profile = profile
        self.level = level
        self.compatibilityID = compatibilityID
        self.source = source
    }
}

public struct HDRMetadata: Codable, Hashable, Sendable {
    public var format: HDRFormat
    public var colorPrimaries: ColorPrimaries
    public var transferFunction: TransferFunction
    public var matrixCoefficients: MatrixCoefficients
    public var bitDepth: Int?
    public var masteringDisplay: MasteringDisplayMetadata?
    public var contentLightLevel: ContentLightLevelMetadata?
    public var dolbyVision: DolbyVisionMetadata?

    public init(
        format: HDRFormat = .unknown,
        colorPrimaries: ColorPrimaries = .unknown,
        transferFunction: TransferFunction = .unknown,
        matrixCoefficients: MatrixCoefficients = .unknown,
        bitDepth: Int? = nil,
        masteringDisplay: MasteringDisplayMetadata? = nil,
        contentLightLevel: ContentLightLevelMetadata? = nil,
        dolbyVision: DolbyVisionMetadata? = nil
    ) {
        self.format = format
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.matrixCoefficients = matrixCoefficients
        self.bitDepth = bitDepth
        self.masteringDisplay = masteringDisplay
        self.contentLightLevel = contentLightLevel
        self.dolbyVision = dolbyVision
    }
}

public struct HDRPlaybackReport: Codable, Hashable, Sendable {
    public var detectedHDRFormat: HDRFormat
    public var outputHDRMode: HDRFormat
    public var colorPrimaries: ColorPrimaries
    public var transferFunction: TransferFunction
    public var bitDepth: Int?
    public var dolbyVisionProfile: Int?
    public var toneMappingApplied: Bool
    public var hdrPreserved: Bool
    public var degradationReason: String?

    public init(metadata: HDRMetadata = HDRMetadata(), outputHDRMode: HDRFormat = .unknown, degradationReason: String? = nil) {
        self.detectedHDRFormat = metadata.format
        self.outputHDRMode = outputHDRMode
        self.colorPrimaries = metadata.colorPrimaries
        self.transferFunction = metadata.transferFunction
        self.bitDepth = metadata.bitDepth
        self.dolbyVisionProfile = metadata.dolbyVision?.profile
        self.toneMappingApplied = degradationReason != nil
        self.hdrPreserved = degradationReason == nil && metadata.format != .unknown
        self.degradationReason = degradationReason
    }
}

public enum HDRMetadataMapper {
    public static func primaries(matroska value: Int?) -> ColorPrimaries {
        value == 9 ? .bt2020 : (value == 1 ? .bt709 : .unknown)
    }

    public static func transfer(matroska value: Int?) -> TransferFunction {
        switch value {
        case 16: return .pq
        case 18: return .hlg
        case 1: return .sdr
        default: return .unknown
        }
    }

    public static func matrix(matroska value: Int?) -> MatrixCoefficients {
        switch value {
        case 1: return .bt709
        case 9: return .bt2020NonConstant
        case 10: return .bt2020Constant
        default: return .unknown
        }
    }
}
