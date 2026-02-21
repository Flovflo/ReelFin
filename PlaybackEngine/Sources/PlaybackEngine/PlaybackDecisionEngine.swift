import Foundation
import Shared

public enum PlaybackRoute: Equatable {
    case directPlay(URL)
    case remux(URL)
    case transcode(URL)
}

public struct PlaybackDecision: Equatable {
    public var sourceID: String
    public var route: PlaybackRoute

    public init(sourceID: String, route: PlaybackRoute) {
        self.sourceID = sourceID
        self.route = route
    }
}

public struct DeviceCapabilities: Sendable {
    public var containers: Set<String>
    public var videoCodecs: Set<String>
    public var audioCodecs: Set<String>

    public init(
        containers: Set<String> = ["mp4", "mkv", "mov", "ts", "m4v"],
        videoCodecs: Set<String> = ["h264", "hevc", "av1"],
        audioCodecs: Set<String> = ["aac", "ac3", "eac3", "mp3", "flac"]
    ) {
        self.containers = containers
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
        for source in sources {
            if let directURL = source.directPlayURL, source.supportsDirectPlay, isCompatible(source: source) {
                return PlaybackDecision(sourceID: source.id, route: .directPlay(directURL))
            }
        }

        for source in sources {
            if let remuxURL = source.directStreamURL, source.supportsDirectStream {
                return PlaybackDecision(sourceID: source.id, route: .remux(remuxURL))
            }
        }

        guard let firstSource = sources.first else { return nil }

        if let transcodeURL = firstSource.transcodeURL {
            return PlaybackDecision(sourceID: firstSource.id, route: .transcode(transcodeURL))
        }

        let fallbackURL = buildTranscodeURL(
            itemID: itemID,
            sourceID: firstSource.id,
            configuration: configuration,
            token: token
        )

        return PlaybackDecision(sourceID: firstSource.id, route: .transcode(fallbackURL))
    }

    private func isCompatible(source: MediaSource) -> Bool {
        if let container = source.container?.lowercased(), !capabilities.containers.contains(container) {
            return false
        }

        if let videoCodec = source.videoCodec?.lowercased(), !capabilities.videoCodecs.contains(videoCodec) {
            return false
        }

        if let audioCodec = source.audioCodec?.lowercased(), !capabilities.audioCodecs.contains(audioCodec) {
            return false
        }

        return true
    }

    private func buildTranscodeURL(
        itemID: String,
        sourceID: String,
        configuration: ServerConfiguration,
        token: String?
    ) -> URL {
        var components = URLComponents(
            url: configuration.serverURL.appendingPathComponent("Videos/\(itemID)/master.m3u8"),
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = [
            URLQueryItem(name: "VideoCodec", value: "h264,hevc"),
            URLQueryItem(name: "AudioCodec", value: "aac,mp3,ac3,eac3"),
            URLQueryItem(name: "MaxStreamingBitrate", value: String(configuration.preferredQuality.maxStreamingBitrate)),
            URLQueryItem(name: "MediaSourceId", value: sourceID),
            URLQueryItem(name: "TranscodeReasons", value: "ContainerNotSupported,VideoCodecNotSupported,AudioCodecNotSupported")
        ]

        if let token {
            components.queryItems?.append(URLQueryItem(name: "api_key", value: token))
        }

        return components.url ?? configuration.serverURL
    }
}
