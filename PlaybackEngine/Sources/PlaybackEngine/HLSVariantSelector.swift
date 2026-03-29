import Foundation
import Shared

struct HLSVariantInfo: Equatable, Sendable {
    let streamInfLine: String
    let uriLine: String
    let resolvedURL: URL
    let query: [String: String]
    let codecs: String
    let supplementalCodecs: String
    let videoRange: String
    let bandwidth: Int
    let averageBandwidth: Int
    let frameRate: Double
    let width: Int
    let height: Int

    var normalizedCodec: String {
        if let queryCodec = query["videocodec"] {
            return HLSVariantSelector.normalizedCodec(from: queryCodec)
        }

        let combined = "\(codecs) \(supplementalCodecs)"
        return HLSVariantSelector.normalizedCodec(from: combined)
    }

    var allowsVideoCopy: Bool? {
        guard let value = query["allowvideostreamcopy"] else { return nil }
        return value == "true"
    }

    var isDolbyVisionSignaled: Bool {
        let lower = "\(videoRange) \(codecs) \(supplementalCodecs)".lowercased()
        return lower.contains("dolby")
            || lower.contains("vision")
            || lower.contains("dovi")
            || lower.contains("dvhe")
            || lower.contains("dvh1")
            || lower.contains("db1p")
    }

    var isHDRSignaled: Bool {
        let lower = "\(videoRange) \(codecs) \(supplementalCodecs)".lowercased()
        return isDolbyVisionSignaled
            || lower.contains("pq")
            || lower.contains("hdr")
            || lower.contains("hlg")
            || lower.contains("bt2020")
    }

    var isHEVC: Bool {
        normalizedCodec == "hevc"
    }

    var isH264: Bool {
        normalizedCodec == "h264"
    }

    var isLikely4K: Bool {
        width >= 3_840 || height >= 2_160
    }

    var isSDR: Bool {
        let lower = videoRange.lowercased()
        if lower.isEmpty {
            return false
        }
        return lower.contains("sdr")
    }

    var usesFMP4Transport: Bool {
        let container = query["container"] ?? ""
        let segmentContainer = query["segmentcontainer"] ?? ""
        if !container.isEmpty || !segmentContainer.isEmpty {
            return container == "fmp4" && segmentContainer == "fmp4"
        }
        return true
    }

    var loggingSummary: String {
        "codecs=\(codecs) supplemental=\(supplementalCodecs) videoRange=\(videoRange) bandwidth=\(bandwidth) averageBandwidth=\(averageBandwidth) frameRate=\(frameRate) resolution=\(width)x\(height)"
    }
}

enum StreamVariantInspector {
    static func inspectVariantPlaylist(manifest: String, variantURL: URL) -> VariantPlaylistInspection {
        let lines = manifest
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let mapURI: String? = lines
            .first(where: { $0.hasPrefix("#EXT-X-MAP:") })
            .flatMap { extractQuotedAttribute(named: "URI", fromTagLine: $0) }

        let firstSegmentURI: String? = lines.first(where: { !$0.hasPrefix("#") })
        let mapURL = mapURI.flatMap { resolvePlaylistURI($0, relativeTo: variantURL) }
        let segmentURL = firstSegmentURI.flatMap { resolvePlaylistURI($0, relativeTo: variantURL) }
        let transport = inferTransport(from: firstSegmentURI, mapURI: mapURI, variantURL: variantURL)

        return VariantPlaylistInspection(
            mapURI: mapURI,
            mapURL: mapURL,
            firstSegmentURI: firstSegmentURI,
            firstSegmentURL: segmentURL,
            transport: transport
        )
    }

    static func inferTransport(from variant: HLSVariantInfo, playlist: VariantPlaylistInspection?) -> String {
        if variant.usesFMP4Transport {
            return "fMP4"
        }
        if let playlist, playlist.transport == "fMP4" {
            return "fMP4"
        }
        return "TS"
    }

    private static func inferTransport(from firstSegmentURI: String?, mapURI: String?, variantURL: URL) -> String {
        if let mapURI, mapURI.lowercased().hasSuffix(".mp4") {
            return "fMP4"
        }
        if let first = firstSegmentURI?.lowercased(), first.hasSuffix(".m4s") || first.hasSuffix(".mp4") {
            return "fMP4"
        }
        if variantURL.absoluteString.lowercased().contains("container=fmp4") ||
            variantURL.absoluteString.lowercased().contains("segmentcontainer=fmp4") {
            return "fMP4"
        }
        return "TS"
    }

    private static func resolvePlaylistURI(_ line: String, relativeTo baseURL: URL) -> URL? {
        if let absolute = URL(string: line), absolute.scheme != nil {
            return absolute
        }
        return URL(string: line, relativeTo: baseURL)?.absoluteURL
    }

    private static func extractQuotedAttribute(named name: String, fromTagLine line: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard
            let match = regex.firstMatch(in: line, options: [], range: range),
            match.numberOfRanges > 1,
            let valueRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return String(line[valueRange])
    }
}

struct VariantPlaylistInspection: Equatable, Sendable {
    let mapURI: String?
    let mapURL: URL?
    let firstSegmentURI: String?
    let firstSegmentURL: URL?
    let transport: String
}

enum HLSVariantSelector {
    static func parseVariants(manifest: String, masterURL: URL) -> [HLSVariantInfo] {
        let lines = manifest
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var variants: [HLSVariantInfo] = []
        var currentStreamInf: String?

        for line in lines where !line.isEmpty {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                currentStreamInf = String(line.dropFirst("#EXT-X-STREAM-INF:".count))
                continue
            }

            guard let streamInf = currentStreamInf else { continue }
            if line.hasPrefix("#") {
                continue
            }

            guard let resolvedURL = resolveVariantURL(line, relativeTo: masterURL) else {
                currentStreamInf = nil
                continue
            }

            let query = queryMap(from: resolvedURL)
            let codecs = parseStringAttribute("CODECS", from: streamInf) ?? ""
            let supplemental = parseStringAttribute("SUPPLEMENTAL-CODECS", from: streamInf) ?? ""
            let videoRange = parseStringAttribute("VIDEO-RANGE", from: streamInf) ?? ""
            let bandwidth = parseIntAttribute("BANDWIDTH", from: streamInf)
            let averageBandwidth = parseIntAttribute("AVERAGE-BANDWIDTH", from: streamInf)
            let frameRate = parseDoubleAttribute("FRAME-RATE", from: streamInf)
            let (width, height) = parseResolution(from: streamInf)

            variants.append(
                HLSVariantInfo(
                    streamInfLine: streamInf,
                    uriLine: line,
                    resolvedURL: resolvedURL,
                    query: query,
                    codecs: codecs,
                    supplementalCodecs: supplemental,
                    videoRange: videoRange,
                    bandwidth: bandwidth,
                    averageBandwidth: averageBandwidth,
                    frameRate: frameRate,
                    width: width,
                    height: height
                )
            )

            currentStreamInf = nil
        }

        return variants
    }

    static func preferredVariant(
        from variants: [HLSVariantInfo],
        playbackPolicy: PlaybackPolicy,
        activeProfile: TranscodeURLProfile,
        source: MediaSource?,
        itemPrefersDolbyVision: Bool,
        allowSDRFallback: Bool,
        strictQualityMode: Bool
    ) -> HLSVariantInfo? {
        guard !variants.isEmpty else { return nil }
        let likelyDolbyVision = itemPrefersDolbyVision || isLikelyDolbyVisionSource(source)
        let likelyHDR = likelyDolbyVision || isLikelyHDRSource(source)

        let pool = filteredVariants(
            from: variants,
            activeProfile: activeProfile,
            playbackPolicy: playbackPolicy,
            likelyHDR: likelyHDR,
            allowSDRFallback: allowSDRFallback,
            strictQualityMode: strictQualityMode
        )

        let sanitizedPool = sanitizedVariants(pool)
        let ranked = sanitizedPool.enumerated().map { index, variant in
            RankedVariant(
                index: index,
                variant: variant,
                codecRank: codecPriority(
                    for: variant,
                    activeProfile: activeProfile,
                    playbackPolicy: playbackPolicy,
                    likelyDolbyVision: likelyDolbyVision
                )
            )
        }

        let sorted = ranked.sorted { lhs, rhs in
            #if os(tvOS)
            // Apple TV 4K: HDR/DV fidelity is more valuable than extra resolution.
            // Prefer DV/HDR variants even at lower resolution (e.g. 720p DV > 1080p SDR).
            if lhs.codecRank != rhs.codecRank { return lhs.codecRank > rhs.codecRank }
            if lhs.variant.height != rhs.variant.height { return lhs.variant.height > rhs.variant.height }
            if lhs.variant.width != rhs.variant.width { return lhs.variant.width > rhs.variant.width }
            #else
            // Resolution is the primary selector to avoid random low-res choices when metadata is noisy.
            if lhs.variant.height != rhs.variant.height { return lhs.variant.height > rhs.variant.height }
            if lhs.variant.width != rhs.variant.width { return lhs.variant.width > rhs.variant.width }
            if lhs.codecRank != rhs.codecRank { return lhs.codecRank > rhs.codecRank }
            #endif
            if lhs.variant.bandwidth != rhs.variant.bandwidth { return lhs.variant.bandwidth > rhs.variant.bandwidth }
            return lhs.index < rhs.index
        }

        return sorted.first?.variant
    }

    static func normalizedCodec(from rawValue: String) -> String {
        let value = rawValue.lowercased()
        if value.contains("h264") || value.contains("avc1") {
            return "h264"
        }
        if value.contains("hevc")
            || value.contains("h265")
            || value.contains("hvc1")
            || value.contains("hev1")
            || value.contains("dvhe")
            || value.contains("dvh1") {
            return "hevc"
        }
        return ""
    }

    private static func codecPriority(
        for variant: HLSVariantInfo,
        activeProfile: TranscodeURLProfile,
        playbackPolicy: PlaybackPolicy,
        likelyDolbyVision: Bool
    ) -> Int {
        switch activeProfile {
        case .forceH264Transcode:
            return variant.isH264 ? 4_000 : 100
        case .appleOptimizedHEVC:
            if variant.isDolbyVisionSignaled { return 3_500 }
            if variant.isHDRSignaled, variant.isHEVC { return 3_300 }
            if variant.isHEVC { return 3_100 }
            return 200
        case .conservativeCompatibility:
            // Stream-copy profile: prefer HDR/DV fidelity since the video bitstream
            // is passed through unmodified. DV variants preserve the original quality.
            if likelyDolbyVision, variant.isDolbyVisionSignaled { return 4_000 }
            if variant.isHDRSignaled, variant.isHEVC { return 3_800 }
            if variant.isHEVC { return playbackPolicy == .auto ? 3_200 : 3_400 }
            return 200
        case .serverDefault:
            if likelyDolbyVision, variant.isDolbyVisionSignaled { return 3_800 }
            if variant.isHDRSignaled, variant.isHEVC { return 3_600 }
            if variant.isHEVC { return playbackPolicy == .auto ? 3_200 : 3_400 }
            return 200
        }
    }

    private static func filteredVariants(
        from variants: [HLSVariantInfo],
        activeProfile: TranscodeURLProfile,
        playbackPolicy: PlaybackPolicy,
        likelyHDR: Bool,
        allowSDRFallback: Bool,
        strictQualityMode: Bool
    ) -> [HLSVariantInfo] {
        func preferNoVideoCopy(_ pool: [HLSVariantInfo]) -> [HLSVariantInfo] {
            let noCopy = pool.filter { $0.allowsVideoCopy == false }
            return noCopy.isEmpty ? pool : noCopy
        }

        switch activeProfile {
        case .forceH264Transcode:
            let h264 = variants.filter(\.isH264)
            let pool = h264.isEmpty ? variants : h264
            return preferNoVideoCopy(pool)
        case .appleOptimizedHEVC:
            let hevc = variants.filter(\.isHEVC)
            let pool = hevc.isEmpty ? variants : hevc
            return preferNoVideoCopy(pool)
        case .serverDefault, .conservativeCompatibility:
            if strictQualityMode, likelyHDR, !allowSDRFallback {
                let hevcHDR = variants.filter { $0.isHEVC && ($0.isHDRSignaled || $0.isDolbyVisionSignaled) }
                if !hevcHDR.isEmpty {
                    return hevcHDR
                }
                return []
            }

            let hevc = variants.filter(\.isHEVC)
            if !hevc.isEmpty {
                return hevc
            }
            return variants
        }
    }

    private static func sanitizedVariants(_ variants: [HLSVariantInfo]) -> [HLSVariantInfo] {
        let filtered = variants.filter { variant in
            // Deterministic guardrail: 4K variants below ~2 Mbps are frequently
            // placeholder/degraded ladders that stall before first decoded frame.
            if variant.width >= 3000,
               variant.height >= 1500,
               variant.bandwidth > 0,
               variant.bandwidth < 2_000_000 {
                return false
            }
            return true
        }

        return filtered.isEmpty ? variants : filtered
    }

    private static func isLikelyDolbyVisionSource(_ source: MediaSource?) -> Bool {
        guard let source else { return false }
        let metadata = [
            source.videoRange?.lowercased() ?? "",
            source.videoCodec?.lowercased() ?? "",
            source.videoProfile?.lowercased() ?? ""
        ].joined(separator: " ")
        let tokens = metadata
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        return metadata.contains("dolby")
            || metadata.contains("vision")
            || tokens.contains("dovi")
            || metadata.contains("dvhe")
            || metadata.contains("dvh1")
    }

    private static func isLikelyHDRSource(_ source: MediaSource?) -> Bool {
        guard let source else { return false }
        let metadata = [
            source.videoRange?.lowercased() ?? "",
            source.videoProfile?.lowercased() ?? ""
        ].joined(separator: " ")
        return metadata.contains("hdr")
            || metadata.contains("pq")
            || metadata.contains("hlg")
            || source.videoBitDepth ?? 8 >= 10
    }

    private struct RankedVariant {
        let index: Int
        let variant: HLSVariantInfo
        let codecRank: Int
    }

    private static func queryMap(from url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        var map: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            map[item.name.lowercased()] = value.lowercased()
        }
        return map
    }

    private static func resolveVariantURL(_ uriLine: String, relativeTo masterURL: URL) -> URL? {
        if let absolute = URL(string: uriLine), absolute.scheme != nil {
            return injectingAPIKeyIfNeeded(targetURL: absolute, from: masterURL)
        }

        guard let resolved = URL(string: uriLine, relativeTo: masterURL)?.absoluteURL else {
            return nil
        }
        return injectingAPIKeyIfNeeded(targetURL: resolved, from: masterURL)
    }

    private static func injectingAPIKeyIfNeeded(targetURL: URL, from masterURL: URL) -> URL {
        guard
            let masterComponents = URLComponents(url: masterURL, resolvingAgainstBaseURL: false),
            let apiKey = masterComponents.queryItems?.first(where: { $0.name.caseInsensitiveCompare("api_key") == .orderedSame })?.value,
            var targetComponents = URLComponents(url: targetURL, resolvingAgainstBaseURL: false)
        else {
            return targetURL
        }

        var queryItems = targetComponents.queryItems ?? []
        if queryItems.contains(where: { $0.name.caseInsensitiveCompare("api_key") == .orderedSame }) {
            return targetURL
        }

        queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        targetComponents.queryItems = queryItems
        return targetComponents.url ?? targetURL
    }

    private static func parseIntAttribute(_ name: String, from attributes: String) -> Int {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))=([0-9]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        guard
            let match = regex.firstMatch(in: attributes, options: [], range: range),
            match.numberOfRanges > 1,
            let valueRange = Range(match.range(at: 1), in: attributes)
        else {
            return 0
        }
        return Int(attributes[valueRange]) ?? 0
    }

    private static func parseDoubleAttribute(_ name: String, from attributes: String) -> Double {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))=([0-9]+(?:\\.[0-9]+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        guard
            let match = regex.firstMatch(in: attributes, options: [], range: range),
            match.numberOfRanges > 1,
            let valueRange = Range(match.range(at: 1), in: attributes)
        else {
            return 0
        }
        return Double(attributes[valueRange]) ?? 0
    }

    private static func parseStringAttribute(_ name: String, from attributes: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\(escaped)=\\\"([^\\\"]+)\\\"|\(escaped)=([^,]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        guard let match = regex.firstMatch(in: attributes, options: [], range: range) else { return nil }

        for group in 1 ..< match.numberOfRanges {
            let nsRange = match.range(at: group)
            guard nsRange.location != NSNotFound, let valueRange = Range(nsRange, in: attributes) else { continue }
            let value = attributes[valueRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func parseResolution(from attributes: String) -> (Int, Int) {
        let pattern = "RESOLUTION=([0-9]+)x([0-9]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return (0, 0) }
        let range = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        guard
            let match = regex.firstMatch(in: attributes, options: [], range: range),
            match.numberOfRanges > 2,
            let widthRange = Range(match.range(at: 1), in: attributes),
            let heightRange = Range(match.range(at: 2), in: attributes)
        else {
            return (0, 0)
        }

        let width = Int(attributes[widthRange]) ?? 0
        let height = Int(attributes[heightRange]) ?? 0
        return (width, height)
    }
}
