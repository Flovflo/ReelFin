import Foundation
import Shared

public struct JellyfinMediaProbe: MediaProbeProtocol {
    public init() {}

    public func probe(itemID: String, source: MediaSource) -> MediaProbeResult {
        let audioTracks = source.audioTracks.map {
            ProbeTrack(
                id: $0.id,
                codec: normalizeAudioCodec(trackCodec: $0.codec, fallback: source.normalizedAudioCodec, title: $0.title),
                language: $0.language,
                isDefault: $0.isDefault,
                isForced: false,
                subtitleKind: nil
            )
        }

        let subtitleTracks = source.subtitleTracks.map {
            ProbeTrack(
                id: $0.id,
                codec: normalizedSubtitleCodec(from: $0.title),
                language: $0.language,
                isDefault: $0.isDefault,
                isForced: titleSuggestsForced($0.title),
                subtitleKind: subtitleKind(from: $0.title)
            )
        }

        return MediaProbeResult(
            itemID: itemID,
            sourceID: source.id,
            container: source.normalizedContainer,
            directPlayURL: source.directPlayURL,
            directStreamURL: source.directStreamURL,
            transcodeURL: source.transcodeURL,
            videoCodec: source.normalizedVideoCodec,
            audioCodec: source.normalizedAudioCodec,
            videoBitDepth: source.videoBitDepth,
            videoRangeType: source.videoRangeType ?? source.videoRange,
            dvProfile: source.dvProfile,
            dvLevel: source.dvLevel,
            dvBlSignalCompatibilityId: source.dvBlSignalCompatibilityId,
            hdr10PlusPresent: source.hdr10PlusPresentFlag ?? false,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            hasKeyframeIndex: source.supportsDirectStream,
            confidence: .server
        )
    }

    private func normalizeAudioCodec(trackCodec: String?, fallback: String, title: String) -> String {
        if let trackCodec, !trackCodec.isEmpty {
            return trackCodec.lowercased()
        }
        let lowerTitle = title.lowercased()
        if lowerTitle.contains("e-ac-3") || lowerTitle.contains("eac3") || lowerTitle.contains("ec3") { return "eac3" }
        if lowerTitle.contains("truehd") || lowerTitle.contains("mlp") { return "truehd" }
        if lowerTitle.contains("ac3") { return "ac3" }
        if lowerTitle.contains("aac") { return "aac" }
        if lowerTitle.contains("dts") { return "dts" }
        return fallback
    }

    private func normalizedSubtitleCodec(from title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("srt") || lower.contains("subrip") { return "srt" }
        if lower.contains("vtt") { return "webvtt" }
        if lower.contains("pgs") || lower.contains("hdmv") { return "pgs" }
        if lower.contains("vobsub") || lower.contains("dvd") { return "vobsub" }
        return "unknown"
    }

    private func subtitleKind(from title: String) -> ProbeSubtitleKind {
        let codec = normalizedSubtitleCodec(from: title)
        switch codec {
        case "srt", "webvtt":
            return .text
        case "pgs", "vobsub":
            return .bitmap
        default:
            return .unknown
        }
    }

    private func titleSuggestsForced(_ title: String) -> Bool {
        title.lowercased().contains("forced")
    }
}
