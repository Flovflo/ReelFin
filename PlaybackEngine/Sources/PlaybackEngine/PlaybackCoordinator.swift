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
    public var playbackPlan: PlaybackPlan?
    public var assetURL: URL
    public var headers: [String: String]
    public var debugInfo: PlaybackDebugInfo

    public init(
        source: MediaSource,
        decision: PlaybackDecision,
        playbackPlan: PlaybackPlan? = nil,
        assetURL: URL,
        headers: [String: String],
        debugInfo: PlaybackDebugInfo
    ) {
        self.source = source
        self.decision = decision
        self.playbackPlan = playbackPlan
        self.assetURL = assetURL
        self.headers = headers
        self.debugInfo = debugInfo
    }
}

public enum TranscodeURLProfile: String, Sendable {
    case serverDefault
    case appleOptimizedHEVC
    case conservativeCompatibility
    case forceH264Transcode
}

public actor PlaybackCoordinator {
    private let apiClient: any JellyfinAPIClientProtocol & Sendable
    private let decisionEngine: PlaybackDecisionEngine
    public let ttffTuning: TTFFTuningConfiguration

    public init(
        apiClient: any JellyfinAPIClientProtocol & Sendable,
        decisionEngine: PlaybackDecisionEngine = PlaybackDecisionEngine()
    ) {
        self.apiClient = apiClient
        self.decisionEngine = decisionEngine
        self.ttffTuning = decisionEngine.ttffTuning
    }

    public func resolvePlayback(
        itemID: String,
        mode: PlaybackMode = .performance,
        allowTranscodingFallbackInPerformance: Bool = true,
        transcodeProfile: TranscodeURLProfile = .serverDefault
    ) async throws -> PlaybackAssetSelection {
        guard
            let configuration = await apiClient.currentConfiguration(),
            let session = await apiClient.currentSession()
        else {
            throw AppError.unauthenticated
        }

        let maxBitrate = configuration.effectiveMaxStreamingBitrate
        let initialOptions = playbackOptions(
            mode: mode,
            maxBitrate: maxBitrate,
            transcodeProfile: transcodeProfile,
            configuration: configuration
        )
        let initialOptionBitrate = initialOptions.maxStreamingBitrate ?? maxBitrate

        let requestInterval = SignpostInterval(signposter: Signpost.playbackInfo, name: "playback_info_request")
        let initialSources = try await apiClient.fetchPlaybackSources(itemID: itemID, options: initialOptions)
        requestInterval.end(name: "playback_info_request", message: "sources_received")

        let selectionInterval = SignpostInterval(signposter: Signpost.playbackSelection, name: "playback_url_selection")

        if let selection = select(
            itemID: itemID,
            sources: initialSources,
            configuration: configuration,
            session: session,
            allowTranscoding: initialOptions.allowTranscoding,
            transcodeProfile: transcodeProfile,
            maxBitrate: initialOptionBitrate
        ) {
            selectionInterval.end(name: "playback_url_selection", message: "selection_complete")
            return selection
        }

        if mode == .performance, allowTranscodingFallbackInPerformance, !initialOptions.allowTranscoding {
            let fallbackOptions = playbackOptions(
                mode: .balanced,
                maxBitrate: maxBitrate,
                transcodeProfile: transcodeProfile,
                configuration: configuration
            )
            let fallbackBitrate = fallbackOptions.maxStreamingBitrate ?? maxBitrate
            let fallbackRequest = SignpostInterval(signposter: Signpost.playbackInfo, name: "playback_info_request_fallback")
            let fallbackSources = try await apiClient.fetchPlaybackSources(itemID: itemID, options: fallbackOptions)
            fallbackRequest.end(name: "playback_info_request_fallback", message: "fallback_sources_received")

            if let fallbackSelection = select(
                itemID: itemID,
                sources: fallbackSources,
                configuration: configuration,
                session: session,
                allowTranscoding: true,
                transcodeProfile: transcodeProfile,
                maxBitrate: fallbackBitrate
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
        allowTranscoding: Bool,
        transcodeProfile: TranscodeURLProfile,
        maxBitrate: Int
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
        let audioSelection = AudioCompatibilitySelector().selectPreferredAudioTrack(
            from: source.audioTracks,
            fallbackCodec: source.normalizedAudioCodec,
            nativePlayerPath: true
        )
        switch decision.route {
        case let .directPlay(url):
            // Prefer progressive Direct Play (static=true) for fastest TTFF
            if let progressiveURL = decisionEngine.directPlayProgressiveURL(
                itemID: itemID,
                source: source,
                configuration: configuration,
                token: session.token
            ) {
                assetURL = progressiveURL
            } else {
                assetURL = url
            }
        case let .remux(url), let .transcode(url):
            assetURL = url
        case let .nativeBridge(plan):
            assetURL = plan.sourceURL
            if plan.audioAction == .serverTranscode {
                var comps = URLComponents(url: assetURL, resolvingAgainstBaseURL: false)
                var q = comps?.queryItems ?? []
                q.removeAll(where: { $0.name == "static" })
                q.append(URLQueryItem(name: "AudioCodec", value: "aac"))
                q.append(URLQueryItem(name: "VideoCodec", value: "copy"))
                comps?.queryItems = q
                assetURL = comps?.url ?? assetURL
            }
        }

        if let preferredAudioIndex = audioSelection.selectedTrackIndex {
            assetURL = appendingQueryItem(url: assetURL, name: "AudioStreamIndex", value: String(preferredAudioIndex))
        }
        if audioSelection.trueHDWasDeprioritized {
            AppLog.playback.notice("\(PlaybackFailureReason.trueHDDeprioritizedForNativePath.localizedDescription ?? "TrueHD deprioritized", privacy: .public)")
        }

        let effectiveProfile = effectiveTranscodeProfile(
            for: decision.route,
            requestedProfile: transcodeProfile,
            source: source,
            url: assetURL
        )

        if case .transcode = decision.route, effectiveProfile != .serverDefault {
            let effectiveBitrate: Int
            switch effectiveProfile {
            case .appleOptimizedHEVC:
                // 4K HEVC server-side transcoding at 30Mbps overwhelms most servers.
                // Cap at 20Mbps which is high quality for HEVC and server-friendly.
                let is4K = (source.videoWidth ?? 0) >= 3840 || (source.videoHeight ?? 0) >= 2160
                effectiveBitrate = min(maxBitrate, is4K ? 20_000_000 : 30_000_000)
            case .serverDefault, .conservativeCompatibility, .forceH264Transcode:
                effectiveBitrate = maxBitrate
            }
            assetURL = normalizeTranscodeURL(
                assetURL,
                maxBitrate: effectiveBitrate,
                preferredVideoCodec: source.normalizedVideoCodec,
                preferredAudioCodec: audioSelection.selectedCodec,
                profile: effectiveProfile,
                configuration: configuration
            )
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
            audioMode: audioSelection.selectedCodec.uppercased(),
            bitrate: source.bitrate,
            playMethod: decision.playMethod
        )

        let profileLabel: String
        if case .nativeBridge = decision.route {
            profileLabel = "nativeBridge"
        } else if effectiveProfile == transcodeProfile {
            profileLabel = effectiveProfile.rawValue
        } else {
            profileLabel = "\(transcodeProfile.rawValue)->\(effectiveProfile.rawValue)"
        }
        AppLog.playback.info(
            "Playback selected method=\(debug.playMethod, privacy: .public) container=\(debug.container, privacy: .public) video=\(debug.videoCodec, privacy: .public) audio=\(debug.audioMode, privacy: .public) profile=\(profileLabel, privacy: .public)"
        )
        AppLog.playback.debug("Playback URL \(assetURL.absoluteString, privacy: .private(mask: .hash))")

        return PlaybackAssetSelection(
            source: source,
            decision: decision,
            playbackPlan: decision.playbackPlan,
            assetURL: assetURL,
            headers: headers,
            debugInfo: debug
        )
    }

    private func playbackOptions(
        mode: PlaybackMode,
        maxBitrate: Int,
        transcodeProfile: TranscodeURLProfile,
        configuration: ServerConfiguration
    ) -> PlaybackInfoOptions {
        if transcodeProfile == .serverDefault, configuration.playbackPolicy != .auto {
            return PlaybackInfoOptions(
                mode: .balanced,
                enableDirectPlay: true,
                enableDirectStream: true,
                allowTranscoding: true,
                maxStreamingBitrate: maxBitrate,
                allowVideoStreamCopy: true,
                allowAudioStreamCopy: configuration.preferAudioTranscodeOnly ? false : true,
                maxAudioChannels: configuration.preferAudioTranscodeOnly ? 6 : nil,
                deviceProfile: .automatic
            )
        }

        switch transcodeProfile {
        case .appleOptimizedHEVC:
            return .appleOptimizedHEVC(maxStreamingBitrate: maxBitrate)
        case .forceH264Transcode:
            return .compatibilityH264(maxStreamingBitrate: maxBitrate)
        case .serverDefault, .conservativeCompatibility:
            if mode == .performance {
                return .performance(maxStreamingBitrate: maxBitrate)
            }
            return .balanced(maxStreamingBitrate: maxBitrate)
        }
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

    private func appendingQueryItem(url: URL, name: String, value: String) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        queryItems.append(URLQueryItem(name: name, value: value))
        components.queryItems = queryItems
        return components.url ?? url
    }

    private func normalizeTranscodeURL(
        _ url: URL,
        maxBitrate: Int,
        preferredVideoCodec: String,
        preferredAudioCodec: String,
        profile: TranscodeURLProfile,
        configuration: ServerConfiguration
    ) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var map: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value {
                map[item.name] = value
            }
        }

        func setQuery(_ key: String, _ value: String) {
            let matches = Array(map.keys).filter { $0.caseInsensitiveCompare(key) == .orderedSame }
            for existing in matches {
                map.removeValue(forKey: existing)
            }
            map[key] = value
        }

        func removeQuery(_ key: String) {
            let matches = Array(map.keys).filter { $0.caseInsensitiveCompare(key) == .orderedSame }
            for existing in matches {
                map.removeValue(forKey: existing)
            }
        }

        func removePrefixedQueries(_ prefixes: [String]) {
            let existingKeys = Array(map.keys)
            for existing in existingKeys {
                let lower = existing.lowercased()
                if prefixes.contains(where: { lower.hasPrefix($0) }) {
                    map.removeValue(forKey: existing)
                }
            }
        }

        func queryValue(_ key: String) -> String? {
            for (existing, value) in map where existing.caseInsensitiveCompare(key) == .orderedSame {
                return value
            }
            return nil
        }

        switch profile {
        case .serverDefault:
            if configuration.playbackPolicy == .auto {
                return url
            }
            setQuery("AllowVideoStreamCopy", "true")
            if configuration.preferAudioTranscodeOnly {
                setQuery("AllowAudioStreamCopy", "false")
                setQuery("AudioCodec", "aac")
            } else {
                setQuery("AllowAudioStreamCopy", "true")
            }
            if let normalizedVideoCodec = normalizedVideoCodec(preferredVideoCodec), normalizedVideoCodec == "hevc" {
                setQuery("VideoCodec", "hevc")
            } else {
                removeQuery("VideoCodec")
            }
            removeQuery("RequireAvc")
        case .conservativeCompatibility:
            // Keep source video codec whenever possible, but normalize audio/container.
            if let normalizedVideoCodec = normalizedVideoCodec(preferredVideoCodec) {
                setQuery("VideoCodec", normalizedVideoCodec)
            } else {
                removeQuery("VideoCodec")
            }
            setQuery("AllowVideoStreamCopy", "true")
            removeQuery("RequireAvc")
        case .appleOptimizedHEVC:
            // Apple-first profile: force a clean HEVC transcode in fMP4 (hardware-friendly on iOS/macOS/tvOS).
            setQuery("VideoCodec", "hevc")
            setQuery("AllowVideoStreamCopy", "false")
            setQuery("RequireAvc", "false")
            setQuery("TranscodingMaxAudioChannels", "6")
            setQuery("EnableAudioVbrEncoding", "true")
        case .forceH264Transcode:
            // Hard fallback for audio-only/black-screen cases: disable video copy.
            setQuery("VideoCodec", "h264")
            setQuery("AllowVideoStreamCopy", "false")
            setQuery("RequireAvc", "true")
        }

        // Clean stale codec constraints to avoid contradictory transcode requests
        // (for example VideoCodec=h264 + hevc-level=150).
        let selectedCodec = queryValue("VideoCodec")?.lowercased() ?? ""
        switch selectedCodec {
        case "h264":
            removePrefixedQueries(["hevc-"])
        case "hevc":
            removePrefixedQueries(["h264-", "avc-"])
        default:
            removePrefixedQueries(["hevc-", "h264-", "avc-"])
        }

        let useFMP4Container: Bool
        switch profile {
        case .appleOptimizedHEVC:
            useFMP4Container = true
        case .conservativeCompatibility:
            useFMP4Container = (queryValue("VideoCodec")?.lowercased() == "hevc")
        case .serverDefault:
            let resolvedCodec = queryValue("VideoCodec")?.lowercased() ?? normalizedVideoCodec(preferredVideoCodec)
            useFMP4Container = resolvedCodec == "hevc"
        case .forceH264Transcode:
            useFMP4Container = false
        }

        let normalizedAudio = normalizedAudioCodec(preferredAudioCodec)
        let preferBitstreamAudio = normalizedAudio == "eac3" || normalizedAudio == "ac3"
        if configuration.preferAudioTranscodeOnly || profile != .serverDefault {
            setQuery("AudioCodec", preferBitstreamAudio ? normalizedAudio : "aac")
        }
        setQuery("Container", useFMP4Container ? "fmp4" : "ts")
        setQuery("SegmentContainer", useFMP4Container ? "fmp4" : "ts")
        if profile != .serverDefault || configuration.preferAudioTranscodeOnly {
            setQuery("AllowAudioStreamCopy", preferBitstreamAudio ? "true" : "false")
        }
        setQuery("MaxStreamingBitrate", String(maxBitrate))
        let resolvedVideoCodec = queryValue("VideoCodec")?.lowercased() ?? normalizedVideoCodec(preferredVideoCodec)
        let breakOnNonKeyFrames: String
        if profile == .forceH264Transcode {
            // Startup-first fallback: allow segmenting on non-keyframes to reduce
            // transcode startup latency on difficult HEVC/DV sources.
            breakOnNonKeyFrames = "False"
        } else {
            breakOnNonKeyFrames = (resolvedVideoCodec == "h264") ? "True" : "False"
        }
        setQuery("BreakOnNonKeyFrames", breakOnNonKeyFrames)
        setQuery("TranscodeReasons", "ContainerNotSupported,AudioCodecNotSupported")

        // TTFF tuning: inject segment and subtitle parameters
        setQuery("SegmentLength", String(ttffTuning.hlsSegmentLengthSeconds))
        setQuery("MinSegments", String(ttffTuning.hlsMinSegments))
        if ttffTuning.disableSubtitleBurnIn {
            setQuery("SubtitleMethod", "External")
        }

        components.queryItems = map.keys.sorted().map { key in
            URLQueryItem(name: key, value: map[key])
        }
        return components.url ?? url
    }

    private func normalizedVideoCodec(_ value: String) -> String? {
        let codec = value.lowercased()
        if codec.contains("hevc") || codec.contains("h265") || codec.contains("dvhe") || codec.contains("dvh1") {
            return "hevc"
        }
        if codec.contains("h264") || codec.contains("avc1") {
            return "h264"
        }
        return nil
    }

    private func normalizedAudioCodec(_ value: String) -> String {
        let codec = value.lowercased()
        if codec.contains("eac3") || codec.contains("ec3") {
            return "eac3"
        }
        if codec.contains("ac3") {
            return "ac3"
        }
        if codec.contains("aac") {
            return "aac"
        }
        return "aac"
    }

    private func effectiveTranscodeProfile(
        for route: PlaybackRoute,
        requestedProfile: TranscodeURLProfile,
        source: MediaSource,
        url: URL
    ) -> TranscodeURLProfile {
        guard case .transcode = route else { return requestedProfile }
        guard requestedProfile == .serverDefault else { return requestedProfile }

        // Apple-safe default for problematic sources:
        // MKV-family + HEVC/DV should avoid initial video stream copy.
        let container = source.normalizedContainer
        let mkvFamily = container == "mkv" || container == "matroska" || container == "webm"
        let codec = source.normalizedVideoCodec
        let hevcFamily = codec.contains("hevc") || codec.contains("h265") || codec.contains("dvhe") || codec.contains("dvh1")

        if mkvFamily && hevcFamily {
            return .appleOptimizedHEVC
        }

        // Guardrail for URLs already carrying HEVC + video copy on server-default profile.
        // This avoids unstable startup loops on some Jellyfin/Apple combinations.
        let query = queryMap(from: url)
        let queryCodec = query["videocodec"] ?? ""
        let allowVideoCopy = query["allowvideostreamcopy"] == "true"
        if allowVideoCopy, queryCodec.contains("hevc"), mkvFamily {
            return .appleOptimizedHEVC
        }

        return requestedProfile
    }

    private func queryMap(from url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [:]
        }

        var map: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            map[item.name.lowercased()] = value.lowercased()
        }
        return map
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
