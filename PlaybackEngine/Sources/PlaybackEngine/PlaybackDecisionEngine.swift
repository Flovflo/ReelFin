import Foundation
import Shared

public enum PlaybackRoute: Equatable, Sendable {
    case directPlay(URL)
    case remux(URL)
    case transcode(URL)
}

public struct PlaybackDecision: Equatable, Sendable {
    public var sourceID: String
    public var route: PlaybackRoute

    public init(sourceID: String, route: PlaybackRoute) {
        self.sourceID = sourceID
        self.route = route
    }

    public var playMethod: String {
        switch route {
        case .directPlay:
            return "DirectPlay"
        case .remux:
            return "DirectStream"
        case .transcode:
            return "Transcode"
        }
    }
}

public struct DeviceCapabilities: Sendable {
    public var directPlayableContainers: Set<String>
    public var videoCodecs: Set<String>
    public var audioCodecs: Set<String>

    public init(
        directPlayableContainers: Set<String> = ["mp4", "m4v", "mov"],
        videoCodecs: Set<String> = ["h264", "avc1", "hevc", "h265", "dvh1", "dvhe", "av1"],
        audioCodecs: Set<String> = ["aac", "ac3", "eac3", "mp3", "flac", "alac", "opus"]
    ) {
        self.directPlayableContainers = directPlayableContainers
        self.videoCodecs = videoCodecs
        self.audioCodecs = audioCodecs
    }
}

public struct PlaybackDecisionEngine {
    private let capabilities: DeviceCapabilities

    public init(capabilities: DeviceCapabilities = DeviceCapabilities()) {
        self.capabilities = capabilities
    }

    public func decide(
        itemID: String,
        sources: [MediaSource],
        configuration: ServerConfiguration,
        token: String?
    ) -> PlaybackDecision? {
        decide(
            itemID: itemID,
            sources: sources,
            configuration: configuration,
            token: token,
            allowTranscoding: true
        )
    }

    public func decide(
        itemID: String,
        sources: [MediaSource],
        configuration: ServerConfiguration,
        token: String?,
        allowTranscoding: Bool
    ) -> PlaybackDecision? {
        let directBest = sources
            .compactMap { directPlayCandidate(for: $0) }
            .max(by: { $0.score < $1.score })

        if let directBest {
            return PlaybackDecision(sourceID: directBest.source.id, route: .directPlay(directBest.url))
        }

        let remuxBest = sources
            .compactMap { remuxCandidate(for: $0) }
            .max(by: { $0.score < $1.score })

        if let remuxBest {
            return PlaybackDecision(sourceID: remuxBest.source.id, route: .remux(remuxBest.url))
        }

        guard allowTranscoding else {
            return nil
        }

        let transcodeBest = sources
            .compactMap { transcodeCandidate(for: $0) }
            .max(by: { $0.score < $1.score })

        if let transcodeBest {
            return PlaybackDecision(sourceID: transcodeBest.source.id, route: .transcode(transcodeBest.url))
        }

        guard let fallbackSource = bestFallbackSource(from: sources) else { return nil }
        let fallbackURL = buildTranscodeURL(
            itemID: itemID,
            source: fallbackSource,
            configuration: configuration,
            token: token
        )

        return PlaybackDecision(sourceID: fallbackSource.id, route: .transcode(fallbackURL))
    }

    private func directPlayCandidate(for source: MediaSource) -> Candidate? {
        guard source.supportsDirectPlay, let url = source.directPlayURL else { return nil }
        guard isDirectPlayable(source: source, url: url) else { return nil }

        var score = 1_000
        score += qualityBoost(for: source)
        score += 20

        return Candidate(source: source, url: url, score: score)
    }

    private func remuxCandidate(for source: MediaSource) -> Candidate? {
        guard source.supportsDirectStream, let url = source.directStreamURL else { return nil }
        guard isRemuxPlayable(source: source, url: url) else { return nil }

        var score = 700
        score += qualityBoost(for: source)
        if isHLS(url: url) {
            score += 80
        }
        return Candidate(source: source, url: url, score: score)
    }

    private func transcodeCandidate(for source: MediaSource) -> Candidate? {
        guard let url = source.transcodeURL else { return nil }
        var score = 300
        if isHLS(url: url) {
            score += 40
            if url.absoluteString.contains("Container=fmp4") {
                score += 50
            }
        }
        return Candidate(source: source, url: url, score: score)
    }

    private func bestFallbackSource(from sources: [MediaSource]) -> MediaSource? {
        sources.max { lhs, rhs in
            qualityBoost(for: lhs) < qualityBoost(for: rhs)
        }
    }

    private func isDirectPlayable(source: MediaSource, url: URL) -> Bool {
        let container = normalizedContainer(source.container, fallbackURL: url)
        guard capabilities.directPlayableContainers.contains(container) else {
            return false
        }

        if !source.normalizedVideoCodec.isEmpty, !capabilities.videoCodecs.contains(source.normalizedVideoCodec) {
            return false
        }

        if !source.normalizedAudioCodec.isEmpty, !capabilities.audioCodecs.contains(source.normalizedAudioCodec) {
            return false
        }

        return true
    }

    private func isRemuxPlayable(source: MediaSource, url: URL) -> Bool {
        if isHLS(url: url) {
            return true
        }

        let container = normalizedContainer(source.container, fallbackURL: url)
        if capabilities.directPlayableContainers.contains(container) {
            return true
        }

        // MKV is not a first-class AVPlayer container. Accept only when remuxed to HLS.
        if container == "mkv" {
            return false
        }

        return container == "ts" || container == "m2ts"
    }

    private func normalizedContainer(_ rawContainer: String?, fallbackURL: URL) -> String {
        if let rawContainer, !rawContainer.isEmpty {
            return rawContainer.lowercased()
        }

        let ext = fallbackURL.pathExtension.lowercased()
        if ext == "m3u8" {
            return "hls"
        }
        return ext
    }

    private func isHLS(url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8"
    }

    private func qualityBoost(for source: MediaSource) -> Int {
        var score = 0

        let videoCodec = source.normalizedVideoCodec
        if videoCodec.contains("dvh1") || videoCodec.contains("dvhe") {
            score += 90
        } else if videoCodec.contains("hevc") || videoCodec.contains("h265") {
            score += 60
        } else if videoCodec.contains("h264") {
            score += 30
        }

        if (source.videoBitDepth ?? 8) >= 10 {
            score += 25
        }

        let range = source.videoRange?.lowercased() ?? ""
        if range.contains("dolby") || range.contains("vision") {
            score += 70
        } else if range.contains("hdr") {
            score += 35
        }

        let audioCodec = source.normalizedAudioCodec
        if audioCodec.contains("eac3") || audioCodec.contains("atmos") {
            score += 50
        } else if audioCodec.contains("ac3") {
            score += 25
        } else if audioCodec.contains("aac") {
            score += 18
        }

        if let layout = source.audioChannelLayout?.lowercased(), layout.contains("atmos") {
            score += 40
        }

        return score
    }

    private func buildTranscodeURL(
        itemID: String,
        source: MediaSource,
        configuration: ServerConfiguration,
        token: String?
    ) -> URL {
        let preferredVideoCodec = preferredVideoCodec(for: source)
        let useFMP4Container = preferredVideoCodec == "hevc"
        var components = URLComponents(
            url: configuration.serverURL.appendingPathComponent("Videos/\(itemID)/master.m3u8"),
            resolvingAgainstBaseURL: false
        )!

        var queryItems = [
            // Keep video close to source whenever possible; force only audio to AAC.
            URLQueryItem(name: "AudioCodec", value: "aac"),
            URLQueryItem(name: "Container", value: useFMP4Container ? "fmp4" : "ts"),
            URLQueryItem(name: "SegmentContainer", value: useFMP4Container ? "fmp4" : "ts"),
            URLQueryItem(name: "AllowVideoStreamCopy", value: "true"),
            URLQueryItem(name: "AllowAudioStreamCopy", value: "false"),
            URLQueryItem(name: "MaxStreamingBitrate", value: String(configuration.preferredQuality.maxStreamingBitrate)),
            URLQueryItem(name: "MediaSourceId", value: source.id),
            URLQueryItem(name: "TranscodeReasons", value: "ContainerNotSupported,AudioCodecNotSupported")
        ]

        if let preferredVideoCodec {
            queryItems.append(URLQueryItem(name: "VideoCodec", value: preferredVideoCodec))
        }

        if let token {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }

        components.queryItems = queryItems
        return components.url ?? configuration.serverURL
    }

    private func preferredVideoCodec(for source: MediaSource) -> String? {
        let codec = source.normalizedVideoCodec

        if codec.contains("hevc") || codec.contains("h265") || codec.contains("dvhe") || codec.contains("dvh1") {
            return "hevc"
        }
        if codec.contains("h264") || codec.contains("avc1") {
            return "h264"
        }
        return nil
    }
}

private struct Candidate {
    let source: MediaSource
    let url: URL
    let score: Int
}
