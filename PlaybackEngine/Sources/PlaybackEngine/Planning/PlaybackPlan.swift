import Foundation

public enum PlaybackLane: String, Sendable, Codable {
    case nativeDirectPlay
    case jitRepackageHLS
    case surgicalFallback
    case rejected
}

public enum PlannedHDRMode: String, Sendable, Codable {
    case dolbyVision
    case hdr10
    case hlg
    case sdr
    case passthrough
}

public enum PlannedSubtitleMode: String, Sendable, Codable {
    case none
    case native
    case webVTT
    case burnIn
    case customOverlay
}

public enum PlannedSeekMode: String, Sendable, Codable {
    case cueDriven
    case keyframeDriven
    case serverManaged
}

public enum FallbackAction: String, Sendable, Codable {
    case selectAlternateAudio
    case audioTranscodeOnly
    case subtitleBurnIn
    case fullTranscode
    case reject
}

public struct PlaybackPlan: Sendable, Equatable, Codable {
    public let itemID: String
    public let sourceID: String?
    public let lane: PlaybackLane
    public let targetURL: URL?

    public let selectedVideoCodec: String?
    public let selectedAudioCodec: String?
    public let selectedSubtitleCodec: String?

    public let hdrMode: PlannedHDRMode
    public let subtitleMode: PlannedSubtitleMode
    public let seekMode: PlannedSeekMode

    public let fallbackGraph: [FallbackAction]
    public let reasonChain: PlaybackReasonChain

    public init(
        itemID: String,
        sourceID: String?,
        lane: PlaybackLane,
        targetURL: URL?,
        selectedVideoCodec: String?,
        selectedAudioCodec: String?,
        selectedSubtitleCodec: String?,
        hdrMode: PlannedHDRMode,
        subtitleMode: PlannedSubtitleMode,
        seekMode: PlannedSeekMode,
        fallbackGraph: [FallbackAction],
        reasonChain: PlaybackReasonChain
    ) {
        self.itemID = itemID
        self.sourceID = sourceID
        self.lane = lane
        self.targetURL = targetURL
        self.selectedVideoCodec = selectedVideoCodec
        self.selectedAudioCodec = selectedAudioCodec
        self.selectedSubtitleCodec = selectedSubtitleCodec
        self.hdrMode = hdrMode
        self.subtitleMode = subtitleMode
        self.seekMode = seekMode
        self.fallbackGraph = fallbackGraph
        self.reasonChain = reasonChain
    }
}

public extension PlaybackPlan {
    static func rejection(itemID: String, sourceID: String?, traces: [PlanDecisionTrace], code: String) -> PlaybackPlan {
        var chain = PlaybackReasonChain(traces: traces)
        chain.append(
            PlanDecisionTrace(
                stage: .finalization,
                outcome: .rejected,
                code: code,
                message: "No playable lane available"
            )
        )
        return PlaybackPlan(
            itemID: itemID,
            sourceID: sourceID,
            lane: .rejected,
            targetURL: nil,
            selectedVideoCodec: nil,
            selectedAudioCodec: nil,
            selectedSubtitleCodec: nil,
            hdrMode: .sdr,
            subtitleMode: .none,
            seekMode: .serverManaged,
            fallbackGraph: [.reject],
            reasonChain: chain
        )
    }
}
