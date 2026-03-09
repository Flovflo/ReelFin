import Foundation
import Shared

public enum PlaybackRoute: Equatable, Sendable {
    case directPlay(URL)
    case remux(URL)
    case transcode(URL)
    case nativeBridge(NativeBridgePlan)
}

public struct PlaybackDecision: Equatable, Sendable {
    public var sourceID: String
    public var route: PlaybackRoute
    public var playbackPlan: PlaybackPlan?

    public init(sourceID: String, route: PlaybackRoute, playbackPlan: PlaybackPlan? = nil) {
        self.sourceID = sourceID
        self.route = route
        self.playbackPlan = playbackPlan
    }

    public var playMethod: String {
        switch route {
        case .directPlay:
            return "DirectPlay"
        case .remux:
            return "DirectStream"
        case .transcode:
            return "Transcode"
        case .nativeBridge:
            return "NativeBridge"
        }
    }
}

public struct MediaSelectionOptionDescriptor: Sendable, Equatable {
    public let optionIndex: Int
    public let displayName: String
    public let languageIdentifier: String?
    public let extendedLanguageTag: String?
    public let isForced: Bool

    public init(
        optionIndex: Int,
        displayName: String,
        languageIdentifier: String? = nil,
        extendedLanguageTag: String? = nil,
        isForced: Bool = false
    ) {
        self.optionIndex = optionIndex
        self.displayName = displayName
        self.languageIdentifier = languageIdentifier
        self.extendedLanguageTag = extendedLanguageTag
        self.isForced = isForced
    }
}

public enum PlaybackTrackMatcher {
    public static func bestOptionIndex(
        for track: MediaTrack,
        options: [MediaSelectionOptionDescriptor]
    ) -> Int? {
        guard !options.isEmpty else { return nil }

        let targetTitle = normalize(track.title)
        let targetLanguage = normalize(track.language ?? "")
        let targetCodec = normalize(track.codec ?? "")
        let trackLooksForced = targetTitle.contains("forced")

        var best: (index: Int, score: Int)?

        for option in options {
            let optionTitle = normalize(option.displayName)
            let optionLanguage = normalize(option.languageIdentifier ?? option.extendedLanguageTag ?? "")

            var score = 0

            if !targetTitle.isEmpty {
                if optionTitle == targetTitle {
                    score += 120
                } else if optionTitle.contains(targetTitle) || targetTitle.contains(optionTitle) {
                    score += 90
                }
            }

            if !targetLanguage.isEmpty, !optionLanguage.isEmpty {
                if optionLanguage == targetLanguage {
                    score += 80
                } else if optionLanguage.hasPrefix(targetLanguage) || targetLanguage.hasPrefix(optionLanguage) {
                    score += 55
                }
            }

            if !targetCodec.isEmpty, optionTitle.contains(targetCodec) {
                score += 25
            }

            if trackLooksForced, option.isForced {
                score += 40
            }

            if score > 0 {
                if let best, best.score >= score {
                    continue
                }
                best = (option.optionIndex, score)
            }
        }

        return best?.index
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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

public enum PlaybackQualityMode: String, Sendable, Equatable {
    case strictQuality
    case compatibility
}

public enum EffectivePlaybackVideoMode: String, Sendable, Equatable {
    case sdr
    case hdr10
    case dolbyVision
    case unknown
}

public enum PlaybackFailureReason: Error, LocalizedError, Sendable, Equatable {
    case strictModeRejectedSDRVariant
    case strictModeRequiresFMP4Transport
    case strictModeBlockedDestructiveTranscode
    case strictModeNoHDRCapablePath
    case unsupportedAssetURL(String)
    case missingDolbyVisionBoxesFallingBackToHDR10
    case subtitleWouldForceDestructiveTranscode
    case trueHDDeprioritizedForNativePath

    public var errorDescription: String? {
        switch self {
        case .strictModeRejectedSDRVariant:
            return "Strict quality mode rejected an SDR stream for HDR/DV source media."
        case .strictModeRequiresFMP4Transport:
            return "Strict quality mode requires HLS fMP4 transport for HDR/DV playback."
        case .strictModeBlockedDestructiveTranscode:
            return "Strict quality mode blocked a transcode profile that would drop HDR metadata."
        case .strictModeNoHDRCapablePath:
            return "No HDR-capable playback path is available in strict quality mode."
        case .unsupportedAssetURL(let url):
            return "Unsupported playback URL for AVFoundation: \(url)"
        case .missingDolbyVisionBoxesFallingBackToHDR10:
            return "Dolby Vision metadata was not preserved in init segment; falling back to HDR10."
        case .subtitleWouldForceDestructiveTranscode:
            return "Selected subtitle would force destructive transcode; strict mode refused it."
        case .trueHDDeprioritizedForNativePath:
            return "TrueHD was deprioritized in favor of Apple-compatible E-AC-3/AAC."
        }
    }
}

public struct PlaybackCapabilityEvaluator: Sendable {
    public init() {}

    public func isHDRorDVSource(_ source: MediaSource) -> Bool {
        source.isLikelyHDRorDV
    }
}

public struct HDRDVPolicy: Sendable {
    public init() {}

    public func qualityMode(for source: MediaSource, configuration: ServerConfiguration) -> PlaybackQualityMode {
        if configuration.playbackPolicy == .originalLockHDRDV {
            return .strictQuality
        }
        // Keep strict mode only when user disabled SDR fallback for HDR/DV content.
        // In auto/originalFirst we prioritize successful native playback and allow server fallback.
        if source.isLikelyHDRorDV, configuration.allowSDRFallback == false {
            return .strictQuality
        }
        return .compatibility
    }

    public func transcodeLooksHDRSafe(url: URL?) -> Bool {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        var map: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            map[item.name.lowercased()] = value.lowercased()
        }

        let videoCodec = map["videocodec"] ?? ""
        let container = map["container"] ?? ""
        let segmentContainer = map["segmentcontainer"] ?? ""
        if videoCodec.contains("h264") || videoCodec.contains("avc1") {
            return false
        }
        return container == "fmp4" && segmentContainer == "fmp4"
    }

    func validateStrictVariant(source: MediaSource, variant: HLSVariantInfo) -> PlaybackFailureReason? {
        guard source.isLikelyHDRorDV else { return nil }
        if variant.isSDR {
            return .strictModeRejectedSDRVariant
        }
        if !variant.usesFMP4Transport {
            return .strictModeRequiresFMP4Transport
        }
        if variant.isH264 {
            return .strictModeBlockedDestructiveTranscode
        }
        return nil
    }
}

public struct AudioCompatibilitySelection: Sendable, Equatable {
    public let selectedCodec: String
    public let selectedTrackIndex: Int?
    public let reason: String
    public let prefersDirectCopy: Bool
    public let trueHDWasDeprioritized: Bool
}

public struct AudioCompatibilitySelector: Sendable {
    public init() {}

    public func selectPreferredAudioTrack(
        from tracks: [MediaTrack],
        fallbackCodec: String,
        nativePlayerPath: Bool
    ) -> AudioCompatibilitySelection {
        struct Candidate {
            let codec: String
            let index: Int?
            let score: Int
            let isTrueHD: Bool
        }

        func codec(from track: MediaTrack) -> String {
            if let explicit = track.codec?.lowercased(), !explicit.isEmpty {
                return explicit
            }
            let title = track.title.lowercased()
            if title.contains("e-ac-3") || title.contains("eac3") || title.contains("ec3") { return "eac3" }
            if title.contains("truehd") || title.contains("mlp") { return "truehd" }
            if title.contains("ac3") { return "ac3" }
            if title.contains("aac") { return "aac" }
            if title.contains("dts") { return "dts" }
            return fallbackCodec.lowercased()
        }

        let candidates: [Candidate] = tracks.map { track in
            let codecValue = codec(from: track)
            var score = 0
            if nativePlayerPath {
                // For AVPlayer-first playback, prioritize AAC for fastest/most reliable startup.
                if codecValue.contains("aac") {
                    score += 10_500
                } else if codecValue.contains("eac3") || codecValue.contains("ec3") {
                    score += 9_500
                } else if codecValue.contains("ac3") {
                    score += 8_500
                } else if codecValue.contains("truehd") {
                    score += 100
                }
            } else if codecValue.contains("eac3") || codecValue.contains("ec3") {
                score += 10_000
            } else if codecValue.contains("ac3") {
                score += 8_000
            } else if codecValue.contains("aac") {
                score += 7_000
            } else if codecValue.contains("truehd") {
                score += 100
            }
            if track.isDefault {
                score += 500
            }
            return Candidate(
                codec: codecValue,
                index: track.index,
                score: score,
                isTrueHD: codecValue.contains("truehd")
            )
        }

        let fallback = fallbackCodec.lowercased()
        let winner = candidates.max(by: { $0.score < $1.score })
        let selectedCodec = winner?.codec.isEmpty == false ? winner!.codec : (fallback.isEmpty ? "aac" : fallback)
        let prefersDirectCopy = selectedCodec.contains("eac3") || selectedCodec.contains("ac3") || selectedCodec.contains("aac")
        let trueHDDeprioritized = nativePlayerPath && (winner?.isTrueHD == false) && fallback.contains("truehd")

        let reason: String
        if trueHDDeprioritized {
            reason = "E-AC-3/AC-3 preferred over TrueHD for Apple native playback compatibility"
        } else if selectedCodec.contains("eac3") || selectedCodec.contains("ec3") {
            reason = "E-AC-3 selected for native Apple playback"
        } else {
            reason = "Selected best compatible audio codec (\(selectedCodec))"
        }

        return AudioCompatibilitySelection(
            selectedCodec: selectedCodec,
            selectedTrackIndex: winner?.index,
            reason: reason,
            prefersDirectCopy: prefersDirectCopy,
            trueHDWasDeprioritized: trueHDDeprioritized
        )
    }
}

public struct SubtitleCompatibilityPolicy: Sendable {
    public init() {}

    public func shouldBlockSubtitleSelection(track: MediaTrack, strictMode: Bool, sourceIsHDRorDV: Bool) -> Bool {
        guard strictMode, sourceIsHDRorDV else { return false }
        let lower = "\(track.title) \(track.codec ?? "")".lowercased()
        let isBitmapSubtitle = lower.contains("pgs") || lower.contains("hdmv") || lower.contains("vobsub")
        return isBitmapSubtitle
    }
}

public struct AssetURLValidator: Sendable {
    public init() {}

    public func validate(url: URL) -> PlaybackFailureReason? {
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "http" || scheme == "https" || scheme == "file" || scheme == NativeBridgeResourceLoader.customScheme {
            return nil
        }
        return .unsupportedAssetURL(url.absoluteString)
    }
}

public struct PlaybackDecisionEngine: Sendable {
    private let capabilities: DeviceCapabilities
    private let capabilityEngine: CapabilityEngineProtocol
    private let mediaProbe: any MediaProbeProtocol
    private let capabilityEvaluator = PlaybackCapabilityEvaluator()
    private let hdrdvPolicy = HDRDVPolicy()
    private let audioSelector = AudioCompatibilitySelector()
    public let ttffTuning: TTFFTuningConfiguration

    public init(
        capabilities: DeviceCapabilities = DeviceCapabilities(),
        ttffTuning: TTFFTuningConfiguration = .default,
        capabilityEngine: CapabilityEngineProtocol = CapabilityEngine(),
        mediaProbe: any MediaProbeProtocol = JellyfinMediaProbe()
    ) {
        self.capabilities = capabilities
        self.ttffTuning = ttffTuning
        self.capabilityEngine = capabilityEngine
        self.mediaProbe = mediaProbe
    }

    private static var isNativeBridgeEnabled: Bool {
        return false
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
        if let rawDecision = rawDirectPlayDecision(
            itemID: itemID,
            sources: sources,
            configuration: configuration,
            token: token
        ) {
            return rawDecision
        }

        let probes = sources.map { mediaProbe.probe(itemID: itemID, source: $0) }
        let planningInput = PlaybackPlanningInput(
            itemID: itemID,
            probes: probes,
            device: DeviceCapabilityFingerprint.current(),
            constraints: .init(),
            allowTranscoding: allowTranscoding
        )
        let playbackPlan = capabilityEngine.computePlan(input: planningInput)

        if let plannedDecision = decisionFromPlan(
            playbackPlan,
            sources: sources,
            itemID: itemID,
            configuration: configuration,
            token: token
        ) {
            return plannedDecision
        }

        let directBest = sources
            .compactMap { directPlayCandidate(for: $0, itemID: itemID, configuration: configuration, token: token) }
            .max(by: { $0.score < $1.score })

        if let directBest {
            return PlaybackDecision(
                sourceID: directBest.source.id,
                route: .directPlay(directBest.url),
                playbackPlan: playbackPlan
            )
        }

        if Self.isNativeBridgeEnabled, !NativeBridgeFailureCache.isDisabled(itemID: itemID) {
            let bridgeBest = sources
                .compactMap { nativeBridgeCandidate(for: $0, itemID: itemID, configuration: configuration) }
                .max(by: { $0.score < $1.score })

            if let bridgeBest {
                return PlaybackDecision(
                    sourceID: bridgeBest.source.id,
                    route: .nativeBridge(bridgeBest.plan),
                    playbackPlan: playbackPlan
                )
            }
        }

        let remuxBest = sources
            .compactMap { remuxCandidate(for: $0, configuration: configuration) }
            .max(by: { $0.score < $1.score })

        if let remuxBest {
            return PlaybackDecision(
                sourceID: remuxBest.source.id,
                route: .remux(remuxBest.url),
                playbackPlan: playbackPlan
            )
        }

        guard allowTranscoding else {
            return nil
        }

        let transcodeBest = sources
            .compactMap { transcodeCandidate(for: $0, configuration: configuration) }
            .max(by: { $0.score < $1.score })

        if let transcodeBest {
            return PlaybackDecision(
                sourceID: transcodeBest.source.id,
                route: .transcode(transcodeBest.url),
                playbackPlan: playbackPlan
            )
        }

        guard let fallbackSource = bestFallbackSource(from: sources) else { return nil }
        if qualityMode(for: fallbackSource, configuration: configuration) == .strictQuality {
            return nil
        }
        let fallbackURL = buildTranscodeURL(
            itemID: itemID,
            source: fallbackSource,
            configuration: configuration,
            token: token
        )

        return PlaybackDecision(
            sourceID: fallbackSource.id,
            route: .transcode(fallbackURL),
            playbackPlan: playbackPlan
        )
    }

    private func rawDirectPlayDecision(
        itemID: String,
        sources: [MediaSource],
        configuration: ServerConfiguration,
        token: String?
    ) -> PlaybackDecision? {
        let ranked = sources.sorted { qualityBoost(for: $0) > qualityBoost(for: $1) }

        for source in ranked {
            guard let rawURL = rawDirectURL(
                for: source,
                itemID: itemID,
                configuration: configuration,
                token: token
            ) else {
                continue
            }

            guard !isHLS(url: rawURL), isDirectPlayable(source: source, url: rawURL) else {
                continue
            }

            if qualityMode(for: source, configuration: configuration) == .strictQuality,
               !isStrictRouteAllowed(source: source, route: .directPlay(rawURL)) {
                continue
            }

            return PlaybackDecision(sourceID: source.id, route: .directPlay(rawURL))
        }

        return nil
    }

    private func rawDirectURL(
        for source: MediaSource,
        itemID: String,
        configuration: ServerConfiguration,
        token: String?
    ) -> URL? {
        if let direct = source.directPlayURL {
            return direct
        }

        if let stream = source.directStreamURL, !isHLS(url: stream) {
            return stream
        }

        let containers = normalizedContainers(source.container, fallbackURL: configuration.serverURL)
        let appleContainer = containers.contains(where: { capabilities.directPlayableContainers.contains($0) })
        guard appleContainer else { return nil }

        return constructDirectStreamURL(itemID: itemID, sourceID: source.id, configuration: configuration, token: token)
    }

    private func decisionFromPlan(
        _ plan: PlaybackPlan,
        sources: [MediaSource],
        itemID: String,
        configuration: ServerConfiguration,
        token: String?
    ) -> PlaybackDecision? {
        guard plan.lane != .rejected else { return nil }
        guard let sourceID = plan.sourceID, let source = sources.first(where: { $0.id == sourceID }) else {
            return nil
        }

        switch plan.lane {
        case .nativeDirectPlay:
            guard let url = directPlayableURL(for: source, itemID: itemID, configuration: configuration, token: token)
                ?? plan.targetURL else { return nil }
            if qualityMode(for: source, configuration: configuration) == .strictQuality,
               !isStrictRouteAllowed(source: source, route: .directPlay(url)) {
                return nil
            }
            return PlaybackDecision(sourceID: sourceID, route: .directPlay(url), playbackPlan: plan)
        case .jitRepackageHLS:
            // For Apple-native containers, do not force a transcode lane just because
            // the planner selected jit packaging. Prefer direct play/remux when valid.
            let container = source.normalizedContainer
            let isAppleContainer = container == "mp4" || container == "m4v" || container == "mov"
            if isAppleContainer {
                if let directURL = directPlayableURL(for: source, itemID: itemID, configuration: configuration, token: token),
                   isDirectPlayable(source: source, url: directURL) {
                    if qualityMode(for: source, configuration: configuration) == .strictQuality,
                       !isStrictRouteAllowed(source: source, route: .directPlay(directURL)) {
                        return nil
                    }
                    return PlaybackDecision(sourceID: sourceID, route: .directPlay(directURL), playbackPlan: plan)
                }
                if source.supportsDirectStream, let remuxURL = source.directStreamURL, isRemuxPlayable(source: source, url: remuxURL) {
                    if qualityMode(for: source, configuration: configuration) == .strictQuality,
                       !isStrictRouteAllowed(source: source, route: .remux(remuxURL)) {
                        return nil
                    }
                    return PlaybackDecision(sourceID: sourceID, route: .remux(remuxURL), playbackPlan: plan)
                }
            }

            // NativeBridge is intentionally disabled for production playback.
            // Route this lane to server-provided remux/transcode outputs only.
            if let transcodeURL = source.transcodeURL ?? plan.targetURL {
                if qualityMode(for: source, configuration: configuration) == .strictQuality,
                   !isStrictRouteAllowed(source: source, route: .transcode(transcodeURL)) {
                    return nil
                }
                return PlaybackDecision(sourceID: sourceID, route: .transcode(transcodeURL), playbackPlan: plan)
            }

            if let remuxURL = source.directStreamURL, isHLS(url: remuxURL) {
                if qualityMode(for: source, configuration: configuration) == .strictQuality,
                   !isStrictRouteAllowed(source: source, route: .remux(remuxURL)) {
                    return nil
                }
                return PlaybackDecision(sourceID: sourceID, route: .remux(remuxURL), playbackPlan: plan)
            }

            // Last resort: force a server transcode URL build instead of exposing raw MKV.
            let fallbackURL = buildTranscodeURL(
                itemID: itemID,
                source: source,
                configuration: configuration,
                token: token
            )
            if qualityMode(for: source, configuration: configuration) == .strictQuality,
               !isStrictRouteAllowed(source: source, route: .transcode(fallbackURL)) {
                return nil
            }
            return PlaybackDecision(sourceID: sourceID, route: .transcode(fallbackURL), playbackPlan: plan)
        case .surgicalFallback:
            if let url = source.transcodeURL ?? plan.targetURL {
                if qualityMode(for: source, configuration: configuration) == .strictQuality,
                   !isStrictRouteAllowed(source: source, route: .transcode(url)) {
                    return nil
                }
                return PlaybackDecision(sourceID: sourceID, route: .transcode(url), playbackPlan: plan)
            }
            let fallbackURL = buildTranscodeURL(
                itemID: itemID,
                source: source,
                configuration: configuration,
                token: token
            )
            if qualityMode(for: source, configuration: configuration) == .strictQuality,
               !isStrictRouteAllowed(source: source, route: .transcode(fallbackURL)) {
                return nil
            }
            return PlaybackDecision(sourceID: sourceID, route: .transcode(fallbackURL), playbackPlan: plan)
        case .rejected:
            return nil
        }
    }

    private func directPlayCandidate(
        for source: MediaSource,
        itemID: String,
        configuration: ServerConfiguration,
        token: String?
    ) -> Candidate? {
        guard let url = directPlayableURL(for: source, itemID: itemID, configuration: configuration, token: token) else {
            return nil
        }
        guard isDirectPlayable(source: source, url: url) else { return nil }
        if qualityMode(for: source, configuration: configuration) == .strictQuality,
           !isStrictRouteAllowed(source: source, route: .directPlay(url)) {
            return nil
        }

        var score = 1_000
        score += qualityBoost(for: source)
        score += 20

        return Candidate(source: source, url: url, score: score)
    }

    private func directPlayableURL(
        for source: MediaSource,
        itemID: String,
        configuration: ServerConfiguration,
        token: String?
    ) -> URL? {
        rawDirectURL(for: source, itemID: itemID, configuration: configuration, token: token)
    }

    private func remuxCandidate(for source: MediaSource, configuration: ServerConfiguration) -> Candidate? {
        guard source.supportsDirectStream, let url = source.directStreamURL else { return nil }
        guard isRemuxPlayable(source: source, url: url) else { return nil }
        if qualityMode(for: source, configuration: configuration) == .strictQuality,
           !isStrictRouteAllowed(source: source, route: .remux(url)) {
            return nil
        }

        var score = 700
        score += qualityBoost(for: source)
        if isHLS(url: url) {
            score += 80
        }
        return Candidate(source: source, url: url, score: score)
    }

    private func nativeBridgeCandidate(for source: MediaSource, itemID: String, configuration: ServerConfiguration) -> BridgeCandidate? {
        // Native Bridge is primarily for MKV files with HEVC/H.264
        guard source.container?.lowercased() == "mkv" else { return nil }
        
        // We need a direct stream URL to read from. If server didn't provide one,
        // construct it using the known Jellyfin API pattern.
        let url: URL
        if let provided = source.directStreamURL ?? source.directPlayURL {
            url = provided
        } else if let constructed = constructDirectStreamURL(itemID: itemID, sourceID: source.id, configuration: configuration, token: nil) {
            url = constructed
        } else {
            return nil
        }

        let fp = DeviceCapabilityFingerprint.current()
        let videoCodec = source.normalizedVideoCodec

        let supportsVideo = (videoCodec == "hevc" && fp.supportsHEVC) ||
                            (videoCodec == "h264" && fp.supportsH264) ||
                            (videoCodec.contains("av1") && fp.supportsAV1)
        
        guard supportsVideo else { return nil }

        // Construct mock track info from source metadata for the pipeline plan
        let transferCharacteristic: Int?
        let transferLower = (source.colorTransfer ?? "").lowercased()
        if transferLower.contains("pq") || transferLower.contains("2084") {
            transferCharacteristic = 16
        } else if transferLower.contains("hlg") {
            transferCharacteristic = 18
        } else {
            transferCharacteristic = nil
        }

        let colourPrimaries: Int?
        let primariesLower = (source.colorPrimaries ?? "").lowercased()
        if primariesLower.contains("2020") {
            colourPrimaries = 9
        } else if primariesLower.contains("709") {
            colourPrimaries = 1
        } else {
            colourPrimaries = nil
        }

        let vTrack = TrackInfo(
            id: 1, trackType: .video, codecID: "", codecName: videoCodec,
            bitDepth: source.videoBitDepth,
            colourPrimaries: colourPrimaries,
            transferCharacteristic: transferCharacteristic
        )
        
        let aTrack: TrackInfo?
        let audioAction: NativeBridgePlan.AudioAction
        let audioSelection = audioSelector.selectPreferredAudioTrack(
            from: source.audioTracks,
            fallbackCodec: source.normalizedAudioCodec,
            nativePlayerPath: true
        )
        let audioCodec = audioSelection.selectedCodec

        let aCodecSupport = AudioCodecSupport.classify(audioCodec)
        if aCodecSupport == .native {
            aTrack = TrackInfo(
                id: 2, trackType: .audio, codecID: "", codecName: audioCodec
            )
            audioAction = .directPassthrough
        } else {
            // Need server audio transcode fallback
            aTrack = TrackInfo(id: 2, trackType: .audio, codecID: "", codecName: "aac")
            audioAction = .serverTranscode
        }

        let plan = NativeBridgePlan(
            itemID: itemID,
            sourceID: source.id,
            sourceURL: url,
            videoTrack: vTrack,
            audioTrack: aTrack,
            videoAction: .directPassthrough,
            audioAction: audioAction,
            subtitleTracks: [],
            videoRangeType: source.videoRangeType ?? source.videoRange,
            dvProfile: source.dvProfile,
            dvLevel: source.dvLevel,
            dvBlSignalCompatibilityId: source.dvBlSignalCompatibilityId,
            hdr10PlusPresentFlag: source.hdr10PlusPresentFlag,
            whyChosen: "Container: MKV, Video: \(videoCodec), Audio: \(audioCodec), reason: \(audioSelection.reason)"
        )

        var score = 850 // Higher than remux, lower than direct play
        score += qualityBoost(for: source)

        return BridgeCandidate(source: source, plan: plan, score: score)
    }

    private func transcodeCandidate(for source: MediaSource, configuration: ServerConfiguration) -> Candidate? {
        guard let url = source.transcodeURL else { return nil }
        if qualityMode(for: source, configuration: configuration) == .strictQuality,
           !isStrictRouteAllowed(source: source, route: .transcode(url)) {
            return nil
        }
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
        let containers = normalizedContainers(source.container, fallbackURL: url)
        guard containers.contains(where: { capabilities.directPlayableContainers.contains($0) }) else {
            return false
        }

        if !source.normalizedVideoCodec.isEmpty, !capabilities.videoCodecs.contains(source.normalizedVideoCodec) {
            return false
        }

        let sourceAudioSupported = source.normalizedAudioCodec.isEmpty || capabilities.audioCodecs.contains(source.normalizedAudioCodec)
        let anyTrackSupported = source.audioTracks.contains { track in
            guard let codec = track.codec?.lowercased(), !codec.isEmpty else { return false }
            return capabilities.audioCodecs.contains(codec)
        }
        if !sourceAudioSupported && !anyTrackSupported {
            return false
        }

        return true
    }

    private func isRemuxPlayable(source: MediaSource, url: URL) -> Bool {
        if isHLS(url: url) {
            return true
        }

        let containers = normalizedContainers(source.container, fallbackURL: url)
        if containers.contains(where: { capabilities.directPlayableContainers.contains($0) }) {
            return true
        }

        // MKV is not a first-class AVPlayer container. Accept only when remuxed to HLS.
        if containers.contains("mkv") || containers.contains("matroska") || containers.contains("webm") {
            return false
        }

        return containers.contains("ts") || containers.contains("m2ts")
    }

    private func normalizedContainers(_ rawContainer: String?, fallbackURL: URL) -> [String] {
        if let rawContainer, !rawContainer.isEmpty {
            let tokens = rawContainer
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            if !tokens.isEmpty {
                return tokens
            }
        }

        let ext = fallbackURL.pathExtension.lowercased()
        if ext == "m3u8" {
            return ["hls"]
        }
        return [ext]
    }

    private func isHLS(url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8"
    }

    /// Construct a direct stream URL for NativeBridge when the server doesn't provide one.
    /// Uses the Jellyfin /Videos/{itemId}/stream endpoint with static=true for raw file access.
    private func constructDirectStreamURL(
        itemID: String,
        sourceID: String,
        configuration: ServerConfiguration,
        token: String?
    ) -> URL? {
        var components = URLComponents(
            url: configuration.serverURL.appendingPathComponent("Videos/\(itemID)/stream"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: sourceID)
        ]
        if let token {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }
        components?.queryItems = queryItems
        return components?.url
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
        let mode = qualityMode(for: source, configuration: configuration)
        let audioSelection = audioSelector.selectPreferredAudioTrack(
            from: source.audioTracks,
            fallbackCodec: source.normalizedAudioCodec,
            nativePlayerPath: true
        )
        let selectedAudioCodec = audioSelection.selectedCodec.isEmpty ? "aac" : audioSelection.selectedCodec
        let allowAudioCopyInStrict = mode == .strictQuality && audioSelection.prefersDirectCopy && !selectedAudioCodec.contains("truehd")
        let allowAudioCopy = allowAudioCopyInStrict
            || (!configuration.preferAudioTranscodeOnly && audioSelection.prefersDirectCopy && !selectedAudioCodec.contains("truehd"))
        let requestedAudioCodec = selectedAudioCodec.contains("truehd") ? "eac3" : selectedAudioCodec

        var components = URLComponents(
            url: configuration.serverURL.appendingPathComponent("Videos/\(itemID)/master.m3u8"),
            resolvingAgainstBaseURL: false
        )!

        var queryItems = [
            // Keep source video bitstream when possible; prefer Apple-native E-AC-3 for multichannel.
            URLQueryItem(name: "AudioCodec", value: requestedAudioCodec),
            URLQueryItem(name: "Container", value: useFMP4Container ? "fmp4" : "ts"),
            URLQueryItem(name: "SegmentContainer", value: useFMP4Container ? "fmp4" : "ts"),
            URLQueryItem(name: "AllowVideoStreamCopy", value: "true"),
            URLQueryItem(name: "AllowAudioStreamCopy", value: allowAudioCopy ? "true" : "false"),
            URLQueryItem(name: "MaxStreamingBitrate", value: String(configuration.effectiveMaxStreamingBitrate)),
            URLQueryItem(name: "MediaSourceId", value: source.id),
            URLQueryItem(name: "TranscodeReasons", value: "ContainerNotSupported,AudioCodecNotSupported"),
            // TTFF tuning: shorter segments → faster first frame
            URLQueryItem(name: "SegmentLength", value: String(ttffTuning.hlsSegmentLengthSeconds)),
            URLQueryItem(name: "MinSegments", value: String(ttffTuning.hlsMinSegments))
        ]

        if let selectedTrackIndex = audioSelection.selectedTrackIndex {
            queryItems.append(URLQueryItem(name: "AudioStreamIndex", value: String(selectedTrackIndex)))
        }

        // Prevent subtitle burn-in which forces a full transcode pipeline
        if ttffTuning.disableSubtitleBurnIn {
            queryItems.append(URLQueryItem(name: "SubtitleMethod", value: "External"))
        }

        if let preferredVideoCodec {
            queryItems.append(URLQueryItem(name: "VideoCodec", value: preferredVideoCodec))
        }

        if let token {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }

        components.queryItems = queryItems
        return components.url ?? configuration.serverURL
    }

    /// Build a progressive download URL for true Direct Play.
    /// This bypasses HLS manifest overhead entirely — the fastest path to first frame.
    public func directPlayProgressiveURL(
        itemID: String,
        source: MediaSource,
        configuration: ServerConfiguration,
        token: String?
    ) -> URL? {
        // OpenAPI source:
        // /Users/florian/Downloads/jellyfin-openapi-stable.json
        // $.paths["/Videos/{itemId}/stream"].get (query parameter: static=true)
        guard ttffTuning.preferProgressiveDirectPlay else { return nil }
        if let providedURL = source.directPlayURL ?? source.directStreamURL {
            let serverHost = configuration.serverURL.host?.lowercased()
            let providedHost = providedURL.host?.lowercased()
            if let serverHost, let providedHost, serverHost != providedHost {
                return nil
            }
        }

        var components = URLComponents(
            url: configuration.serverURL.appendingPathComponent("Videos/\(itemID)/stream"),
            resolvingAgainstBaseURL: false
        )

        var queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "MediaSourceId", value: source.id)
        ]

        if let token {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }

        components?.queryItems = queryItems
        return components?.url
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

    private func qualityMode(for source: MediaSource, configuration: ServerConfiguration) -> PlaybackQualityMode {
        hdrdvPolicy.qualityMode(for: source, configuration: configuration)
    }

    private func isStrictRouteAllowed(source: MediaSource, route: PlaybackRoute) -> Bool {
        guard capabilityEvaluator.isHDRorDVSource(source) else { return true }

        switch route {
        case .nativeBridge:
            return true
        case .remux(let routeURL), .transcode(let routeURL), .directPlay(let routeURL):
            return isStrictRouteAllowed(source: source, url: routeURL, route: route)
        }
    }

    private func isStrictRouteAllowed(source: MediaSource, url: URL, route: PlaybackRoute) -> Bool {
        switch route {
        case .directPlay:
            let ext = url.pathExtension.lowercased()
            return source.normalizedContainer != "mkv" && ext != "mkv"
        case .remux:
            return url.pathExtension.lowercased() == "m3u8" || source.supportsDirectStream
        case .transcode:
            return hdrdvPolicy.transcodeLooksHDRSafe(url: url)
        case .nativeBridge:
            return true
        }
    }
}

private struct Candidate {
    let source: MediaSource
    let url: URL
    let score: Int
}

private struct BridgeCandidate {
    let source: MediaSource
    let plan: NativeBridgePlan
    let score: Int
}
