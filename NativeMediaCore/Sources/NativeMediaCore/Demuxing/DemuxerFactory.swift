import Foundation

public enum DemuxerFactoryError: LocalizedError, Sendable, Equatable {
    case noLocalDemuxer(ContainerFormat)

    public var errorDescription: String? {
        switch self {
        case .noLocalDemuxer(let format):
            return "No local demuxer backend exists yet for \(format.rawValue)."
        }
    }
}

public struct DemuxerFactory: Sendable {
    public var allowCustomDemuxers: Bool
    public var enableExperimentalMKV: Bool

    public init(allowCustomDemuxers: Bool = true, enableExperimentalMKV: Bool = true) {
        self.allowCustomDemuxers = allowCustomDemuxers
        self.enableExperimentalMKV = enableExperimentalMKV
    }

    public func makeDemuxer(
        format: ContainerFormat,
        source: any MediaByteSource,
        sourceURL: URL
    ) throws -> any MediaDemuxer {
        switch format {
        case .mp4, .mov:
            return try MP4Demuxer(url: sourceURL, format: format)
        case .matroska, .webm:
            guard allowCustomDemuxers, enableExperimentalMKV else {
                throw DemuxerFactoryError.noLocalDemuxer(format)
            }
            return MatroskaDemuxer(source: source, profile: format == .webm ? .webm : .matroska)
        case .mpegTS, .m2ts:
            guard allowCustomDemuxers else {
                throw DemuxerFactoryError.noLocalDemuxer(format)
            }
            return MPEGTransportStreamDemuxer(source: source, format: format)
        default:
            throw DemuxerFactoryError.noLocalDemuxer(format)
        }
    }
}
