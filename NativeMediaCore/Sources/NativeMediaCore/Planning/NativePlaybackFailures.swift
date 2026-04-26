import Foundation

public enum FallbackReason: LocalizedError, Sendable, Equatable {
    case decoderBackendMissing(codec: String)
    case matroskaPacketExtractionIncomplete(trackID: Int)
    case videoToolboxFormatDescriptionFailed(codecPrivateReason: String)
    case hdrMetadataDetectedButNotPreserved(reason: String)
    case serverTranscodeBlockedByConfig
    case demuxerUnavailable(container: ContainerFormat)
    case rendererUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .decoderBackendMissing(let codec):
            return "No local decoder backend exists yet for \(codec)."
        case .matroskaPacketExtractionIncomplete(let trackID):
            return "Matroska packet extraction is incomplete for track \(trackID)."
        case .videoToolboxFormatDescriptionFailed(let reason):
            return "VideoToolbox format description failed: \(reason)."
        case .hdrMetadataDetectedButNotPreserved(let reason):
            return "HDR metadata was detected but not preserved: \(reason)."
        case .serverTranscodeBlockedByConfig:
            return "Server transcode fallback exists but is disabled by NativePlayerConfig."
        case .demuxerUnavailable(let container):
            return "No local demuxer is available for \(container.rawValue)."
        case .rendererUnavailable(let reason):
            return "No renderer is available: \(reason)."
        }
    }
}
