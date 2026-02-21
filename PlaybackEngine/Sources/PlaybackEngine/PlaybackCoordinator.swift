import Foundation
import Shared

public enum HDRPlaybackMode: String, Sendable {
    case dolbyVision = "Dolby Vision"
    case hdr10 = "HDR10"
    case sdr = "SDR"
    case unknown = "Unknown"
}

public struct PlaybackDebugInfo: Equatable, Sendable {
    public var container: String
    public var videoCodec: String
    public var videoBitDepth: Int?
    public var hdrMode: HDRPlaybackMode
    public var audioMode: String
    public var bitrate: Int?
    public var playMethod: String

    public init(
        container: String,
        videoCodec: String,
        videoBitDepth: Int?,
        hdrMode: HDRPlaybackMode,
        audioMode: String,
        bitrate: Int?,
        playMethod: String
    ) {
        self.container = container
        self.videoCodec = videoCodec
        self.videoBitDepth = videoBitDepth
        self.hdrMode = hdrMode
        self.audioMode = audioMode
        self.bitrate = bitrate
        self.playMethod = playMethod
    }
}

public struct PlaybackAssetSelection: Sendable {
    public var source: MediaSource
    public var decision: PlaybackDecision
    public var assetURL: URL
    public var headers: [String: String]
    public var debugInfo: PlaybackDebugInfo

    public init(
        source: MediaSource,
        decision: PlaybackDecision,
        assetURL: URL,
        headers: [String: String],
        debugInfo: PlaybackDebugInfo
    ) {
        self.source = source
        self.decision = decision
        self.assetURL = assetURL
        self.headers = headers
        self.debugInfo = debugInfo
    }
}

public actor PlaybackCoordinator {
    private let apiClient: JellyfinAPIClientProtocol
    private let decisionEngine: PlaybackDecisionEngine

    public init(
        apiClient: JellyfinAPIClientProtocol,
        decisionEngine: PlaybackDecisionEngine = PlaybackDecisionEngine()
    ) {
        self.apiClient = apiClient
        self.decisionEngine = decisionEngine
    }

    public func resolvePlayback(
        itemID: String,
        mode: PlaybackMode = .performance,
        allowTranscodingFallbackInPerformance: Bool = true
    ) async throws -> PlaybackAssetSelection {
        guard
            let configuration = await apiClient.currentConfiguration(),
            let session = await apiClient.currentSession()
        else {
            throw AppError.unauthenticated
        }

        let maxBitrate = configuration.preferredQuality.maxStreamingBitrate
        let initialOptions: PlaybackInfoOptions = mode == .performance
            ? .performance(maxStreamingBitrate: maxBitrate)
            : .balanced(maxStreamingBitrate: maxBitrate)

        let requestInterval = SignpostInterval(signposter: Signpost.playbackInfo, name: "playback_info_request")
        let initialSources = try await apiClient.fetchPlaybackSources(itemID: itemID, options: initialOptions)
        requestInterval.end(name: "playback_info_request", message: "sources_received")

        let selectionInterval = SignpostInterval(signposter: Signpost.playbackSelection, name: "playback_url_selection")

        if let selection = select(
            itemID: itemID,
            sources: initialSources,
            configuration: configuration,
            session: session,
            allowTranscoding: initialOptions.allowTranscoding
        ) {
            selectionInterval.end(name: "playback_url_selection", message: "selection_complete")
            return selection
        }

        if mode == .performance, allowTranscodingFallbackInPerformance {
            let fallbackOptions = PlaybackInfoOptions.balanced(maxStreamingBitrate: maxBitrate)
            let fallbackRequest = SignpostInterval(signposter: Signpost.playbackInfo, name: "playback_info_request_fallback")
            let fallbackSources = try await apiClient.fetchPlaybackSources(itemID: itemID, options: fallbackOptions)
            fallbackRequest.end(name: "playback_info_request_fallback", message: "fallback_sources_received")

            if let fallbackSelection = select(
                itemID: itemID,
                sources: fallbackSources,
                configuration: configuration,
                session: session,
                allowTranscoding: true
            ) {
                selectionInterval.end(name: "playback_url_selection", message: "fallback_selection_complete")
                return fallbackSelection
            }
        }

        selectionInterval.end(name: "playback_url_selection", message: "selection_failed")
        throw AppError.network("No playable media source available for this device.")
    }

    private func select(
        itemID: String,
        sources: [MediaSource],
        configuration: ServerConfiguration,
        session: UserSession,
        allowTranscoding: Bool
    ) -> PlaybackAssetSelection? {
        guard let decision = decisionEngine.decide(
            itemID: itemID,
            sources: sources,
            configuration: configuration,
            token: session.token,
            allowTranscoding: allowTranscoding
        ) else {
            return nil
        }

        guard let source = sources.first(where: { $0.id == decision.sourceID }) else {
            return nil
        }

        var assetURL: URL
        switch decision.route {
        case let .directPlay(url), let .remux(url), let .transcode(url):
            assetURL = url
        }

        // HLS segment/key fetches are more reliable when auth is present in URL query.
        assetURL = injectingAPIKeyIfNeeded(assetURL, token: session.token)

        var headers = source.requiredHTTPHeaders
        headers["X-Emby-Token"] = session.token

        let debug = PlaybackDebugInfo(
            container: source.container ?? "unknown",
            videoCodec: source.videoCodec ?? "unknown",
            videoBitDepth: source.videoBitDepth,
            hdrMode: classifyHDRMode(for: source),
            audioMode: classifyAudioMode(for: source),
            bitrate: source.bitrate,
            playMethod: decision.playMethod
        )

        AppLog.playback.info(
            "Playback selected method=\(debug.playMethod, privacy: .public) container=\(debug.container, privacy: .public) video=\(debug.videoCodec, privacy: .public) audio=\(debug.audioMode, privacy: .public)"
        )

        return PlaybackAssetSelection(
            source: source,
            decision: decision,
            assetURL: assetURL,
            headers: headers,
            debugInfo: debug
        )
    }

    private func injectingAPIKeyIfNeeded(_ url: URL, token: String) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var queryItems = components.queryItems ?? []
        if queryItems.contains(where: { $0.name.caseInsensitiveCompare("api_key") == .orderedSame }) {
            return url
        }

        queryItems.append(URLQueryItem(name: "api_key", value: token))
        components.queryItems = queryItems
        return components.url ?? url
    }

    private func classifyHDRMode(for source: MediaSource) -> HDRPlaybackMode {
        let value = [
            source.videoRange?.lowercased() ?? "",
            source.videoCodec?.lowercased() ?? "",
            source.videoProfile?.lowercased() ?? ""
        ].joined(separator: " ")

        if value.contains("dolby") || value.contains("vision") || value.contains("dvhe") || value.contains("dvh1") {
            return .dolbyVision
        }
        if value.contains("hdr10") || value.contains("hdr") || value.contains("pq") {
            return .hdr10
        }
        if value.isEmpty {
            return .unknown
        }
        return .sdr
    }

    private func classifyAudioMode(for source: MediaSource) -> String {
        let codec = source.audioCodec?.lowercased() ?? ""
        let layout = source.audioChannelLayout?.lowercased() ?? ""
        let profile = source.audioProfile?.lowercased() ?? ""
        let combined = "\(codec) \(layout) \(profile)"

        if combined.contains("atmos") {
            return "Dolby Atmos"
        }
        if codec.contains("eac3") {
            return "E-AC-3"
        }
        if codec.contains("ac3") {
            return "AC-3"
        }
        if codec.contains("aac") {
            return "AAC"
        }
        if codec.isEmpty {
            return "Unknown"
        }
        return codec.uppercased()
    }
}
