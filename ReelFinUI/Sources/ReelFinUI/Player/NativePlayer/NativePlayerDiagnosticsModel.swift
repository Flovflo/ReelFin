import Foundation
import NativeMediaCore

/// Typed view over the sample-buffer diagnostic rows.
///
/// The player previously re-scanned the raw rows with independent `contains`/prefix
/// passes on every SwiftUI body evaluation (buffering state, container, HDR quality
/// label, accessibility fields). This model parses each field exactly once per
/// publication so consumers read typed values instead of re-walking the rows.
struct NativePlayerDiagnosticsModel: Equatable {
    let isBuffering: Bool
    let containerFormat: ContainerFormat
    let isPacketDemuxedContainer: Bool
    let qualityLabel: String
    let accessibility: NativePlayerAccessibilityDiagnostics

    /// - Parameters:
    ///   - baseRows: session-provided overlay lines (container routing lives here).
    ///   - liveRows: player-published rows; when non-empty they supersede the base
    ///     rows for playback-state fields, matching the previous `activeDiagnostics`.
    init(baseRows: [String], liveRows: [String]) {
        let activeRows = liveRows.isEmpty ? baseRows : liveRows
        isBuffering = activeRows.contains("state=buffering")

        if baseRows.contains(where: { $0 == "container=webm" }) {
            containerFormat = .webm
        } else if baseRows.contains(where: { $0 == "container=mpegTS" }) {
            containerFormat = .mpegTS
        } else if baseRows.contains(where: { $0 == "container=m2ts" }) {
            containerFormat = .m2ts
        } else {
            containerFormat = .matroska
        }

        isPacketDemuxedContainer = baseRows.contains { line in
            line == "container=matroska"
                || line == "container=webm"
                || line == "container=mpegTS"
                || line == "container=m2ts"
        }

        if let hdrLine = activeRows.first(where: { $0.hasPrefix("hdr=") }),
           !hdrLine.contains("hdr=sdr") {
            qualityLabel = hdrLine.replacingOccurrences(of: "hdr=", with: "").uppercased()
        } else {
            qualityLabel = "Originale"
        }

        accessibility = NativePlayerAccessibilityDiagnostics(rows: activeRows)
    }
}
