import Foundation
import Shared

public enum PlaybackRouteGuaranteeResolver {
    public static func resolve(
        source: MediaSource,
        route: PlaybackRoute,
        finalURL: URL,
        evidence: PlaybackRouteEvidence = .init(),
        selectedSubtitleTrack: MediaTrack? = nil
    ) -> PlaybackRouteGuarantees {
        let query = queryMap(from: finalURL)
        let videoIntegrity = inferVideoIntegrity(source: source, route: route, query: query, subtitle: selectedSubtitleTrack)
        let startupClass = inferStartupClass(route: route, finalURL: finalURL, videoIntegrity: videoIntegrity)
        let hdrIntegrity = inferHDRIntegrity(source: source, route: route, query: query, videoIntegrity: videoIntegrity, evidence: evidence)
        let summary = summary(route: route, videoIntegrity: videoIntegrity, hdrIntegrity: hdrIntegrity, startupClass: startupClass)
        let reason = debugReason(source: source, finalURL: finalURL, videoIntegrity: videoIntegrity, hdrIntegrity: hdrIntegrity, evidence: evidence, subtitle: selectedSubtitleTrack)

        return PlaybackRouteGuarantees(
            videoIntegrity: videoIntegrity,
            hdrIntegrity: hdrIntegrity,
            startupClass: startupClass,
            userVisibleSummary: summary,
            debugReason: reason
        )
    }

    private static func inferVideoIntegrity(source: MediaSource, route: PlaybackRoute, query: [String: String], subtitle: MediaTrack?) -> PlaybackVideoIntegrity {
        if let subtitle, SubtitleCompatibilityPolicy().qualityImpact(track: subtitle, source: source) == .requiresBurnIn {
            return .videoTranscode
        }

        switch route {
        case .directPlay:
            return .originalBitstream
        case .nativeBridge(let plan):
            return plan.audioAction == .serverTranscode ? .audioOnlyTranscode : .originalBitstream
        case .remux, .transcode:
            let videoCopy = query["allowvideostreamcopy"]
            let targetCodec = normalizedCodec(query["videocodec"] ?? query["videocodecs"] ?? "")
            let sourceCodec = normalizedCodec(source.normalizedVideoCodec)
            if videoCopy == "false" { return .videoTranscode }
            if !targetCodec.isEmpty, !sourceCodec.isEmpty, targetCodec != sourceCodec, videoCopy != "true" {
                return .videoTranscode
            }
            if videoCopy == "true" {
                return query["allowaudiostreamcopy"] == "false" ? .audioOnlyTranscode : .videoCopyRemux
            }
            return routeIsRemux(route) ? .videoCopyRemux : .unknown
        }
    }

    private static func inferStartupClass(route: PlaybackRoute, finalURL: URL, videoIntegrity: PlaybackVideoIntegrity) -> PlaybackStartupClass {
        if videoIntegrity == .videoTranscode { return .transcode }
        switch route {
        case .directPlay:
            if finalURL.isFileURL || isLoopback(finalURL) { return .directLocal }
            if isPrivateLAN(finalURL) { return .directLAN }
            return .remoteDirect
        case .nativeBridge:
            return .nativeDirect
        case .remux, .transcode:
            if isHLS(finalURL) { return .hlsRemux }
            return .progressiveRemux
        }
    }

    private static func inferHDRIntegrity(source: MediaSource, route: PlaybackRoute, query: [String: String], videoIntegrity: PlaybackVideoIntegrity, evidence: PlaybackRouteEvidence) -> PlaybackHDRIntegrity {
        if videoIntegrity == .videoTranscode {
            return source.isLikelyHDRorDV ? .sdrToneMapped : .sdr
        }

        let dvClass = DolbyVisionClass.classify(source: source)
        if dvClass.isDolbyVision {
            if dvClass == .profile7DualLayer { return .hdr10FallbackFromDolbyVision }
            if routeIsNativeBridge(route) { return .unknown }
            if routeIsDirect(route), appleDirectDVEvidence(source: source, finalURLQuery: query) { return .dolbyVision }
            if evidence.selectedVariantIsDolbyVisionSignaled,
               evidence.selectedVariantUsesFMP4 != false,
               evidence.initHasDvcC || evidence.initHasDvvC || evidence.selectedVariantCodec?.lowercased().contains("dvh") == true {
                return .dolbyVision
            }
            if dvClass == .profile8_1HDR10Compatible { return .hdr10FallbackFromDolbyVision }
            if dvClass == .profile8_4HLGCompatible { return .hlg }
            return .unknown
        }

        switch PlaybackMediaHDRClass.classify(source: source) {
        case .hdr10, .dolbyVision:
            return .hdr10
        case .hlg:
            return .hlg
        case .sdr:
            return .sdr
        case .unknown:
            return evidence.selectedVariantIsHDRSignaled ? .hdr10 : .unknown
        }
    }

    private static func debugReason(source: MediaSource, finalURL: URL, videoIntegrity: PlaybackVideoIntegrity, hdrIntegrity: PlaybackHDRIntegrity, evidence: PlaybackRouteEvidence, subtitle: MediaTrack?) -> String {
        var parts = ["container=\(source.container ?? "unknown")", "video=\(source.videoCodec ?? "unknown")", "url=\(finalURL.reelfinCompactLogString)"]
        if videoIntegrity == .videoTranscode { parts.append("video copy disabled or target codec changes source bitstream") }
        if hdrIntegrity == .hdr10FallbackFromDolbyVision { parts.append("Dolby Vision not guaranteed; HDR10 fallback only") }
        if let subtitle { parts.append("subtitle=\(subtitle.title)") }
        if evidence.localGatewayEnabled { parts.append("localGateway=true") }
        return parts.joined(separator: "; ")
    }

    private static func summary(route: PlaybackRoute, videoIntegrity: PlaybackVideoIntegrity, hdrIntegrity: PlaybackHDRIntegrity, startupClass: PlaybackStartupClass) -> String {
        let routeName = routeLabel(route: route, startupClass: startupClass)
        return "\(routeName): \(videoIntegrity.rawValue), HDR \(hdrIntegrity.rawValue)"
    }
}

private extension PlaybackRouteGuaranteeResolver {
    static func queryMap(from url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        var map: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            map[item.name.lowercased()] = value.lowercased()
        }
        return map
    }

    static func normalizedCodec(_ codec: String) -> String {
        let lower = codec.lowercased()
        if lower.contains("hevc") || lower.contains("h265") || lower.contains("hvc1") || lower.contains("hev1") || lower.contains("dvh1") || lower.contains("dvhe") { return "hevc" }
        if lower.contains("h264") || lower.contains("avc1") { return "h264" }
        return lower
    }

    static func isHLS(_ url: URL) -> Bool { url.pathExtension.lowercased() == "m3u8" }
    static func routeIsDirect(_ route: PlaybackRoute) -> Bool { if case .directPlay = route { return true }; return false }
    static func routeIsNativeBridge(_ route: PlaybackRoute) -> Bool { if case .nativeBridge = route { return true }; return false }
    static func routeIsRemux(_ route: PlaybackRoute) -> Bool { if case .remux = route { return true }; return false }
}
