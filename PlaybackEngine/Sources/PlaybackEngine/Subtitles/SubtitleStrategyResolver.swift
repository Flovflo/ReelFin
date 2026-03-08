import Foundation

public enum SubtitlePipelineMode: String, Sendable, Equatable {
    case disabled
    case webVTT
    case burnIn
    case customOverlay
}

public struct ResolvedSubtitleStrategy: Sendable, Equatable {
    public let mode: SubtitlePipelineMode
    public let selectedTrackID: String?
    public let reason: String

    public init(mode: SubtitlePipelineMode, selectedTrackID: String?, reason: String) {
        self.mode = mode
        self.selectedTrackID = selectedTrackID
        self.reason = reason
    }
}

public struct SubtitleStrategyResolver: Sendable {
    public init() {}

    public func resolve(
        tracks: [ProbeTrack],
        selectedTrackID: String? = nil,
        preferCustomOverlay: Bool,
        allowBurnIn: Bool
    ) -> ResolvedSubtitleStrategy {
        guard !tracks.isEmpty else {
            return ResolvedSubtitleStrategy(mode: .disabled, selectedTrackID: nil, reason: "No subtitle track available")
        }

        let selected = selectedTrackID.flatMap { id in tracks.first(where: { $0.id == id }) }
            ?? tracks.first(where: { $0.isDefault })
            ?? tracks.first

        guard let selected else {
            return ResolvedSubtitleStrategy(mode: .disabled, selectedTrackID: nil, reason: "No subtitle track selected")
        }

        switch selected.subtitleKind {
        case .text:
            return ResolvedSubtitleStrategy(
                mode: .webVTT,
                selectedTrackID: selected.id,
                reason: "Text subtitle selected (\(selected.codec)); convert to WebVTT"
            )
        case .bitmap:
            if preferCustomOverlay {
                return ResolvedSubtitleStrategy(
                    mode: .customOverlay,
                    selectedTrackID: selected.id,
                    reason: "Bitmap subtitle selected (\(selected.codec)); using custom overlay renderer"
                )
            }
            if allowBurnIn {
                return ResolvedSubtitleStrategy(
                    mode: .burnIn,
                    selectedTrackID: selected.id,
                    reason: "Bitmap subtitle selected (\(selected.codec)); using burn-in fallback"
                )
            }
            return ResolvedSubtitleStrategy(
                mode: .disabled,
                selectedTrackID: selected.id,
                reason: "Bitmap subtitle selected but overlay/burn-in disabled"
            )
        case .unknown, .none:
            return ResolvedSubtitleStrategy(
                mode: .disabled,
                selectedTrackID: selected.id,
                reason: "Unknown subtitle kind; disabling"
            )
        }
    }
}
