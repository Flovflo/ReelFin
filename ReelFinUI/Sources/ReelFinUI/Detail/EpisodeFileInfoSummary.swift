import Foundation
import Shared

struct EpisodeFileInfoRow: Equatable, Sendable {
    let label: String
    let value: String
}

struct EpisodeFileInfoSummary: Equatable, Sendable {
    let rows: [EpisodeFileInfoRow]

    init(source: MediaSource) {
        var resolvedRows: [EpisodeFileInfoRow] = []

        resolvedRows.append(EpisodeFileInfoRow(label: "Route", value: Self.routeLabel(for: source)))

        if let container = Self.containerLabel(for: source.container) {
            resolvedRows.append(EpisodeFileInfoRow(label: "Container", value: container))
        }

        if let video = Self.videoLabel(for: source) {
            resolvedRows.append(EpisodeFileInfoRow(label: "Video", value: video))
        }

        if let audio = Self.audioLabel(for: source) {
            resolvedRows.append(EpisodeFileInfoRow(label: "Audio", value: audio))
        }

        if let bitrate = source.bitrate, bitrate > 0 {
            resolvedRows.append(EpisodeFileInfoRow(label: "Bitrate", value: Self.bitrateLabel(for: bitrate)))
        }

        if let width = source.videoWidth, let height = source.videoHeight, width > 0, height > 0 {
            resolvedRows.append(EpisodeFileInfoRow(label: "Resolution", value: "\(width)x\(height)"))
        }

        if let fileSize = source.fileSize, fileSize > 0 {
            resolvedRows.append(EpisodeFileInfoRow(label: "Size", value: Self.fileSizeLabel(for: fileSize)))
        }

        rows = resolvedRows
    }

    var alertMessage: String {
        rows.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
    }

    func rowValue(label: String) -> String? {
        rows.first { $0.label == label }?.value
    }

    private static func routeLabel(for source: MediaSource) -> String {
        if source.supportsDirectPlay, source.directPlayURL != nil {
            return "Native Direct Play"
        }
        if source.supportsDirectStream, source.directStreamURL != nil {
            return "Native Direct Stream"
        }
        if source.transcodeURL != nil {
            return "Server Transcode"
        }
        if source.supportsDirectPlay {
            return "Direct Play"
        }
        if source.supportsDirectStream {
            return "Direct Stream"
        }
        return "Server Transcode"
    }

    private static func containerLabel(for container: String?) -> String? {
        guard let firstMatch = normalizedParts(from: container).first else { return nil }
        if normalizedParts(from: container).contains("mp4") || normalizedParts(from: container).contains("mov") {
            return "MP4"
        }
        if firstMatch == "mkv" || firstMatch == "matroska" {
            return "MKV"
        }
        if firstMatch == "ts" || firstMatch == "mpegts" {
            return "TS"
        }
        return firstMatch.uppercased()
    }

    private static func videoLabel(for source: MediaSource) -> String? {
        guard let codec = normalizedCodecLabel(source.videoCodec) else { return nil }
        var components = [codec]

        if let bitDepth = source.videoBitDepth, bitDepth > 0 {
            components.append("\(bitDepth)-bit")
        }

        if let range = hdrLabel(range: source.videoRange, rangeType: source.videoRangeType) {
            components.append(range)
        }

        return components.joined(separator: " ")
    }

    private static func audioLabel(for source: MediaSource) -> String? {
        guard let codec = normalizedCodecLabel(source.audioCodec) else { return nil }
        if let channels = source.audioChannels, channels > 0 {
            return "\(codec) \(channels)ch"
        }
        return codec
    }

    private static func normalizedCodecLabel(_ codec: String?) -> String? {
        guard let codec = codec?.trimmingCharacters(in: .whitespacesAndNewlines), !codec.isEmpty else {
            return nil
        }

        switch codec.lowercased() {
        case "h264", "avc":
            return "H.264"
        case "h265", "hevc":
            return "HEVC"
        case "eac3":
            return "EAC3"
        case "aac":
            return "AAC"
        default:
            return codec.uppercased()
        }
    }

    private static func hdrLabel(range: String?, rangeType: String?) -> String? {
        let candidates = [rangeType, range]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for candidate in candidates {
            let normalized = candidate.lowercased()
            if normalized == "sdr" || normalized == "unknown" {
                continue
            }
            if normalized.contains("dovi") || normalized.contains("dolby") {
                return "Dolby Vision"
            }
            if normalized.contains("hdr10") {
                return "HDR10"
            }
            if normalized.contains("hlg") {
                return "HLG"
            }
            if normalized.contains("pq") || normalized.contains("hdr") {
                return candidate.uppercased()
            }
        }

        return nil
    }

    private static func bitrateLabel(for bitrate: Int) -> String {
        String(format: "%.1f Mbps", locale: Locale(identifier: "en_US_POSIX"), Double(bitrate) / 1_000_000)
    }

    private static func fileSizeLabel(for bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1_000, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(value)) \(units[unitIndex])"
        }
        return String(format: "%.2f %@", locale: Locale(identifier: "en_US_POSIX"), value, units[unitIndex])
    }

    private static func normalizedParts(from value: String?) -> [String] {
        value?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty } ?? []
    }
}
