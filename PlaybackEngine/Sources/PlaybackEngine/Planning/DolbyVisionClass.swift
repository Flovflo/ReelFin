import Foundation
import Shared

public enum DolbyVisionClass: String, Codable, Sendable, Equatable {
    case profile5SingleLayer
    case profile8_1HDR10Compatible
    case profile8_4HLGCompatible
    case profile7DualLayer
    case unknown
    case none

    public static func classify(source: MediaSource) -> DolbyVisionClass {
        guard sourceLooksDolbyVision(source) else { return .none }
        guard let profile = source.dvProfile, profile > 0 else { return .unknown }

        switch profile {
        case 5:
            return .profile5SingleLayer
        case 7:
            return .profile7DualLayer
        case 8:
            switch source.dvBlSignalCompatibilityId {
            case 1:
                return .profile8_1HDR10Compatible
            case 4:
                return .profile8_4HLGCompatible
            default:
                let metadata = normalizedMetadata(source)
                if metadata.contains("hdr10") { return .profile8_1HDR10Compatible }
                if metadata.contains("hlg") { return .profile8_4HLGCompatible }
                return .unknown
            }
        default:
            return .unknown
        }
    }

    public var isDolbyVision: Bool {
        self != .none
    }

    private static func sourceLooksDolbyVision(_ source: MediaSource) -> Bool {
        if let profile = source.dvProfile, profile > 0 { return true }
        let metadata = normalizedMetadata(source)
        return metadata.contains("dolby")
            || metadata.contains("vision")
            || metadata.contains("dovi")
            || metadata.contains("dvhe")
            || metadata.contains("dvh1")
    }

    private static func normalizedMetadata(_ source: MediaSource) -> String {
        [
            source.videoRange,
            source.videoRangeType,
            source.videoProfile,
            source.videoCodec
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }
}

public enum PlaybackMediaHDRClass: String, Codable, Sendable, Equatable {
    case dolbyVision
    case hdr10
    case hlg
    case sdr
    case unknown

    public static func classify(source: MediaSource) -> PlaybackMediaHDRClass {
        if DolbyVisionClass.classify(source: source).isDolbyVision {
            return .dolbyVision
        }

        let metadata = [
            source.videoRange,
            source.videoRangeType,
            source.videoProfile,
            source.colorTransfer,
            source.colorSpace
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if metadata.contains("hlg") { return .hlg }
        if metadata.contains("hdr10")
            || metadata.contains("pq")
            || metadata.contains("smpte")
            || metadata.contains("2084")
            || source.hdr10PlusPresentFlag == true {
            return .hdr10
        }
        if source.isLikelyHDRorDV { return .unknown }
        return .sdr
    }
}
