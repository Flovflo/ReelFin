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
        transcodeProfile: TranscodeURLProfile = .serverDefault,
        startTimeTicks: Int64? = nil
    ) async throws -> PlaybackAssetSelection {
        guard
            let configuration = await apiClient.currentConfiguration(),
            let session = await apiClient.currentSession()
        else {
            throw AppError.unauthenticated
        }

        let maxBitrate = configuration.effectiveMaxStreamingBitrate
        var initialOptions = playbackOptions(
            mode: mode,
            maxBitrate: maxBitrate,
            transcodeProfile: transcodeProfile,
            configuration: configuration
        )
        initialOptions.startTimeTicks = startTimeTicks
        let initialOptionBitrate = initialOptions.maxStreamingBitrate ?? maxBitrate

        let requestInterval = SignpostInterval(signposter: Signpost.playbackInfo, name: "playback_info_request")
        let initialSources = try await apiClient.fetchPlaybackSources(itemID: itemID, options: initialOptions)
        requestInterval.end(name: "playback_info_request", message: "sources_received")

        let selectionInterval = SignpostInterval(signposter: Signpost.playbackSelection, name: "playback_url_selection")

        if let selection = try await select(
            itemID: itemID,
            sources: initialSources,
            configuration: configuration,
            session: session,
            allowTranscoding: initialOptions.allowTranscoding,
            transcodeProfile: transcodeProfile,
            maxBitrate: initialOptionBitrate,
            mode: initialOptions.mode,
            startTimeTicks: startTimeTicks
        ) {
            selectionInterval.end(name: "playback_url_selection", message: "selection_complete")
            return selection
        }

        if mode == .performance, allowTranscodingFallbackInPerformance, !initialOptions.allowTranscoding {
            var fallbackOptions = playbackOptions(
                mode: .balanced,
                maxBitrate: maxBitrate,
                transcodeProfile: transcodeProfile,
                configuration: configuration
            )
            fallbackOptions.startTimeTicks = startTimeTicks
            let fallbackBitrate = fallbackOptions.maxStreamingBitrate ?? maxBitrate
            let fallbackRequest = SignpostInterval(signposter: Signpost.playbackInfo, name: "playback_info_request_fallback")
            let fallbackSources = try await apiClient.fetchPlaybackSources(itemID: itemID, options: fallbackOptions)
            fallbackRequest.end(name: "playback_info_request_fallback", message: "fallback_sources_received")

            if let fallbackSelection = try await select(
                itemID: itemID,
                sources: fallbackSources,
                configuration: configuration,
                session: session,
                allowTranscoding: true,
                transcodeProfile: transcodeProfile,
                maxBitrate: fallbackBitrate,
                mode: fallbackOptions.mode,
                startTimeTicks: startTimeTicks
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
        maxBitrate: Int,
        mode: PlaybackMode,
        startTimeTicks: Int64?,
        allowDedicatedProfileRefetch: Bool = true
    ) async throws -> PlaybackAssetSelection? {
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
            nativePlayerPath: true,
            preferredLanguage: configuration.preferredAudioLanguage
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
            AppLog.playback.notice("\(PlaybackFailureReason.trueHDDeprioritizedForNativePath.localizedDescription, privacy: .public)")
        }

        let requestedProfile = forcedProfileIfNeeded(
            route: decision.route,
            configuration: configuration,
            defaultProfile: transcodeProfile
        )

        let effectiveProfile = effectiveTranscodeProfile(
            for: decision.route,
            requestedProfile: requestedProfile,
            source: source,
            url: assetURL
        )

        if allowDedicatedProfileRefetch,
           shouldRefetchDedicatedSources(
               route: decision.route,
               requestedProfile: requestedProfile,
               effectiveProfile: effectiveProfile
           ),
           let dedicatedSelection = try await selectDedicatedProfileSelection(
               itemID: itemID,
               configuration: configuration,
               session: session,
               allowTranscoding: allowTranscoding,
               transcodeProfile: effectiveProfile,
               maxBitrate: maxBitrate,
               mode: mode,
               startTimeTicks: startTimeTicks
           ) {
            return dedicatedSelection
        }

        if !isDirectPlayRoute(decision.route), effectiveProfile != .serverDefault {
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
            if case .remux = decision.route, let transcodeURL = source.transcodeURL {
                assetURL = transcodeURL
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
        } else if effectiveProfile == requestedProfile {
            profileLabel = effectiveProfile.rawValue
        } else {
            profileLabel = "\(requestedProfile.rawValue)->\(effectiveProfile.rawValue)"
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

    private func isDirectPlayRoute(_ route: PlaybackRoute) -> Bool {
        if case .directPlay = route {
            return true
        }
        return false
    }

    private func shouldRefetchDedicatedSources(
        route: PlaybackRoute,
        requestedProfile: TranscodeURLProfile,
        effectiveProfile: TranscodeURLProfile
    ) -> Bool {
        guard requestedProfile != effectiveProfile else { return false }
        switch route {
        case .directPlay, .nativeBridge:
            return false
        case .remux, .transcode:
            return true
        }
    }

    private func selectDedicatedProfileSelection(
        itemID: String,
        configuration: ServerConfiguration,
        session: UserSession,
        allowTranscoding: Bool,
        transcodeProfile: TranscodeURLProfile,
        maxBitrate: Int,
        mode: PlaybackMode,
        startTimeTicks: Int64?
    ) async throws -> PlaybackAssetSelection? {
        var options = playbackOptions(
            mode: mode,
            maxBitrate: maxBitrate,
            transcodeProfile: transcodeProfile,
            configuration: configuration
        )
        options.startTimeTicks = startTimeTicks

        let dedicatedSources = try await apiClient.fetchPlaybackSources(itemID: itemID, options: options)
        let dedicatedBitrate = options.maxStreamingBitrate ?? maxBitrate
        return try await select(
            itemID: itemID,
            sources: dedicatedSources,
            configuration: configuration,
            session: session,
            allowTranscoding: allowTranscoding,
            transcodeProfile: transcodeProfile,
            maxBitrate: dedicatedBitrate,
            mode: options.mode,
            startTimeTicks: startTimeTicks,
            allowDedicatedProfileRefetch: false
        )
    }

    private func forcedProfileIfNeeded(
        route: PlaybackRoute,
        configuration: ServerConfiguration,
        defaultProfile: TranscodeURLProfile
    ) -> TranscodeURLProfile {
        guard configuration.forceH264FallbackWhenNotDirectPlay else {
            return defaultProfile
        }
        return isDirectPlayRoute(route) ? defaultProfile : .forceH264Transcode
    }

    private static var isTvOS: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    nonisolated static func requiresCompatibilityH264Transcode(source: MediaSource) -> Bool {
        let codec = source.normalizedVideoCodec
        guard !codec.isEmpty else { return false }
        guard !isH264Family(codec), !isHEVCFamily(codec) else { return false }
        return true
    }

    private func playbackOptions(
        mode: PlaybackMode,
        maxBitrate: Int,
        transcodeProfile: TranscodeURLProfile,
        configuration: ServerConfiguration
    ) -> PlaybackInfoOptions {
        // On tvOS, always use the tvOS-optimized profile which tells Jellyfin
        // exactly what Apple TV can direct play/remux and what needs transcoding.
        if Self.isTvOS {
            #if targetEnvironment(simulator)
            return .tvOSSimulatorCompatibility(maxStreamingBitrate: maxBitrate)
            #else
            return .tvOSOptimized(maxStreamingBitrate: maxBitrate)
            #endif
        }

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
        let allowAudioCopy: Bool = {
            if let explicit = queryValue("AllowAudioStreamCopy")?.lowercased() {
                return explicit == "true"
            }
            // Honor preferAudioTranscodeOnly for all profiles.
            // (serverDefault + auto policy already returns early above, so is never reached here.)
            return !configuration.preferAudioTranscodeOnly
        }()
        let preferBitstreamAudio = allowAudioCopy && (normalizedAudio == "eac3" || normalizedAudio == "ac3")
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

        // Legacy video codecs exposed through Jellyfin's generic serverDefault HLS
        // path are prone to "readyToPlay but never decodes a frame" failures on AVPlayer.
        // Prefer a real H.264 transcode over stream-copying codecs like AVI/MPEG4.
        if Self.requiresCompatibilityH264Transcode(source: source) {
            return .forceH264Transcode
        }

        // Apple-safe default for problematic sources:
        // MKV-family + HEVC/DV should avoid initial video stream copy.
        let container = source.normalizedContainer
        let mkvFamily = container == "mkv" || container == "matroska" || container == "webm"
        let codec = source.normalizedVideoCodec
        let hevcFamily = codec.contains("hevc") || codec.contains("h265") || codec.contains("dvhe") || codec.contains("dvh1")

        #if os(tvOS)
        // tvOS: ALL MKV transcodes must use H264 TS (forceH264Transcode).
        //
        // Root cause: Jellyfin does NOT produce real fMP4 segments for HEVC HLS.
        // Despite SegmentContainer=fmp4, the actual bytes are MPEG-TS (0x47 sync byte).
        // Apple AVPlayer requires fMP4/CMAF for HEVC HLS — HEVC in TS segments is
        // not supported. AVPlayer reaches readyToPlay but never decodes a frame.
        //
        // This affects ALL MKV transcodes:
        //   - conservativeCompatibility (stream copy HEVC fMP4) → broken
        //   - appleOptimizedHEVC (re-encode HEVC fMP4) → broken
        //   - forceH264Transcode (H264 TS) → WORKS
        //
        // H264 in TS is the only Jellyfin transcode path that produces decodable
        // segments on tvOS. DirectPlay (MOV/MP4) is unaffected.
        if mkvFamily {
            return .forceH264Transcode
        }
        #else
        if mkvFamily && hevcFamily {
            return .appleOptimizedHEVC
        }
        #endif

        // Guardrail for URLs already carrying HEVC + video copy on server-default profile.
        // This avoids unstable startup loops on some Jellyfin/Apple combinations.
        let query = queryMap(from: url)
        let queryCodec = query["videocodec"] ?? ""
        let allowVideoCopy = query["allowvideostreamcopy"] == "true"
        if allowVideoCopy, queryCodec.contains("hevc"), mkvFamily {
            #if os(tvOS)
            return .conservativeCompatibility
            #else
            return .appleOptimizedHEVC
            #endif
        }

        return requestedProfile
    }

    /// Detect Dolby Vision from the video codec string (dvhe, dvh1, dovi).
    private static func isDolbyVisionCodec(_ codec: String) -> Bool {
        let lower = codec.lowercased()
        return lower.contains("dvhe") || lower.contains("dvh1") || lower.contains("dovi")
    }

    private static func isH264Family(_ codec: String) -> Bool {
        let lower = codec.lowercased()
        return lower.contains("h264") || lower.contains("avc1")
    }

    private static func isHEVCFamily(_ codec: String) -> Bool {
        let lower = codec.lowercased()
        return lower.contains("hevc")
            || lower.contains("h265")
            || lower.contains("hvc1")
            || lower.contains("hev1")
            || lower.contains("dvhe")
            || lower.contains("dvh1")
    }

    /// Detect Dolby Vision from broader source metadata (videoRange, videoProfile, videoRangeType).
    private static func isDolbyVisionSource(_ source: MediaSource) -> Bool {
        let metadata = [
            source.videoRange?.lowercased() ?? "",
            source.videoProfile?.lowercased() ?? "",
            source.videoRangeType?.lowercased() ?? "",
            source.videoCodec?.lowercased() ?? ""
        ].joined(separator: " ")
        return metadata.contains("dolby")
            || metadata.contains("vision")
            || metadata.contains("dovi")
            || metadata.contains("dvhe")
            || metadata.contains("dvh1")
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
