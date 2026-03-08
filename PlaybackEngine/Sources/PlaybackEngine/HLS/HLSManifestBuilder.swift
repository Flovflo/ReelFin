import Foundation

public struct HLSMediaPlaylistSegment: Sendable, Equatable {
    public let uri: String
    public let duration: Double

    public init(uri: String, duration: Double) {
        self.uri = uri
        self.duration = duration
    }
}

public struct HLSManifestBuilder: Sendable {
    public init() {}

    public func makeMasterPlaylist(
        videoPlaylistURI: String,
        subtitlePlaylistURI: String? = nil,
        codecs: String,
        supplementalCodecs: String? = nil,
        videoRange: String? = nil,
        resolution: String? = nil,
        bandwidth: Int = 20_000_000,
        averageBandwidth: Int? = nil,
        frameRate: Double? = nil
    ) -> String {
        var lines: [String] = [
            "#EXTM3U",
            "#EXT-X-VERSION:7"
        ]

        if let subtitlePlaylistURI {
            lines.append("#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"Default\",DEFAULT=YES,AUTOSELECT=YES,FORCED=NO,URI=\"\(subtitlePlaylistURI)\"")
        }

        var streamInf = "#EXT-X-STREAM-INF:BANDWIDTH=\(bandwidth),CODECS=\"\(codecs)\""
        if let averageBandwidth, averageBandwidth > 0 {
            streamInf += ",AVERAGE-BANDWIDTH=\(averageBandwidth)"
        }
        if let videoRange, !videoRange.isEmpty {
            streamInf += ",VIDEO-RANGE=\(videoRange)"
        }
        if let supplementalCodecs, !supplementalCodecs.isEmpty {
            streamInf += ",SUPPLEMENTAL-CODECS=\"\(supplementalCodecs)\""
        }
        if let resolution {
            streamInf += ",RESOLUTION=\(resolution)"
        }
        if let frameRate, frameRate > 0 {
            streamInf += ",FRAME-RATE=\(String(format: "%.3f", frameRate))"
        }
        if subtitlePlaylistURI != nil {
            streamInf += ",SUBTITLES=\"subs\""
        }
        lines.append(streamInf)
        lines.append(videoPlaylistURI)
        lines.append("")

        return lines.joined(separator: "\n")
    }

    public func makeMediaPlaylist(
        targetDuration: Int,
        mediaSequence: Int,
        initSegmentURI: String,
        segments: [HLSMediaPlaylistSegment],
        endList: Bool
    ) -> String {
        var lines: [String] = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(max(1, targetDuration))",
            "#EXT-X-MEDIA-SEQUENCE:\(max(0, mediaSequence))",
            "#EXT-X-INDEPENDENT-SEGMENTS"
        ]

        if endList {
            lines.append("#EXT-X-PLAYLIST-TYPE:VOD")
        } else {
            lines.append("#EXT-X-PLAYLIST-TYPE:EVENT")
        }
        lines.append("#EXT-X-MAP:URI=\"\(initSegmentURI)\"")

        for segment in segments {
            lines.append("#EXTINF:\(String(format: "%.3f", segment.duration)),")
            lines.append(segment.uri)
        }

        if endList {
            lines.append("#EXT-X-ENDLIST")
        }
        lines.append("")

        return lines.joined(separator: "\n")
    }
}
