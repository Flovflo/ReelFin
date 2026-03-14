import Foundation
import Shared

// MARK: - Hybrid Capability Engine

/// Deterministic engine selection based on media characteristics.
/// Inspects container, codecs, subtitles, HDR metadata to choose the best playback path.
public struct HybridCapabilityEngine: Sendable {

    public init() {}

    /// Analyze media characteristics and produce a deterministic engine recommendation.
    public func evaluate(_ media: MediaCharacteristics) -> EngineCapabilityDecision {
        var reasons: [ReasonCode] = []
        var startupRisk: RiskLevel = .none
        var subtitleRisk: RiskLevel = .none
        var audioRisk: RiskLevel = .none
        var hdrExpectation: HDRExpectation = .sdr
        var featureCompleteness: Double = 1.0

        // ── Container Analysis ──
        let containerResult = evaluateContainer(media.container)
        reasons.append(contentsOf: containerResult.reasons)

        // ── Video Codec Analysis ──
        let videoResult = evaluateVideoCodec(media.videoCodec, bitDepth: media.bitDepth)
        reasons.append(contentsOf: videoResult.reasons)

        // ── Audio Codec Analysis ──
        let audioResult = evaluateAudioCodec(media.audioCodec)
        reasons.append(contentsOf: audioResult.reasons)
        audioRisk = audioResult.risk

        // ── Subtitle Analysis ──
        let subtitleResult = evaluateSubtitles(media.subtitleCodecs)
        reasons.append(contentsOf: subtitleResult.reasons)
        subtitleRisk = subtitleResult.risk

        // ── HDR / Dynamic Range Analysis ──
        let hdrResult = evaluateHDR(media)
        reasons.append(contentsOf: hdrResult.reasons)
        hdrExpectation = hdrResult.expectation

        // ── Source Type ──
        reasons.append(sourceReason(for: media.sourceType))

        // ── Determine Recommendation ──
        let vlcRequired = containerResult.requiresVLC || videoResult.requiresVLC || audioResult.requiresVLC
        let vlcPreferred = subtitleResult.prefersVLC
        let nativeSafe = containerResult.nativeSafe && videoResult.nativeSafe && audioResult.nativeSafe
        let hasMetadata = media.videoCodec != nil || media.container != nil

        let recommendation: EngineRecommendation
        if !hasMetadata {
            // Insufficient metadata: try native with fallback
            recommendation = .nativeThenFallbackIfStartupFails
            reasons.append(.metadataMissing)
            startupRisk = .medium
            featureCompleteness = 0.5
        } else if media.hasTranscodeURL && !media.supportsDirectPlay && !media.supportsDirectStream {
            // No direct path available but server can transcode
            recommendation = .serverTranscodePreferred
            reasons.append(.fallbackToServerTranscode)
            startupRisk = .low
        } else if vlcRequired {
            recommendation = .vlcRequired
            startupRisk = .none
            featureCompleteness = 0.9
            if hdrExpectation != .sdr {
                reasons.append(.hdrDegradedByVLCFallback)
                hdrExpectation = .hdrDegradedByEngine
                featureCompleteness = 0.85
            }
        } else if nativeSafe && !vlcPreferred {
            if containerResult.risk > .low || videoResult.risk > .low {
                recommendation = .nativeAllowedButRisky
                startupRisk = max(containerResult.risk, videoResult.risk)
                featureCompleteness = 0.9
            } else {
                recommendation = .nativePreferred
                startupRisk = .none
            }
        } else if vlcPreferred {
            // Subtitles or other features prefer VLC but native codec path works
            if nativeSafe {
                recommendation = .nativeThenFallbackIfStartupFails
                startupRisk = .low
                featureCompleteness = 0.9
            } else {
                recommendation = .vlcRequired
                if hdrExpectation != .sdr {
                    reasons.append(.hdrDegradedByVLCFallback)
                    hdrExpectation = .hdrDegradedByEngine
                }
                featureCompleteness = 0.85
            }
        } else {
            recommendation = .nativeThenFallbackIfStartupFails
            startupRisk = .medium
            featureCompleteness = 0.8
        }

        return EngineCapabilityDecision(
            recommendation: recommendation,
            reasons: reasons,
            startupRisk: startupRisk,
            subtitleRisk: subtitleRisk,
            audioRisk: audioRisk,
            hdrExpectation: hdrExpectation,
            estimatedFeatureCompleteness: featureCompleteness
        )
    }

    // MARK: - Container Evaluation

    private struct ContainerResult {
        let reasons: [ReasonCode]
        let nativeSafe: Bool
        let requiresVLC: Bool
        let risk: RiskLevel
    }

    private func evaluateContainer(_ container: String?) -> ContainerResult {
        guard let container = container?.lowercased(), !container.isEmpty else {
            return ContainerResult(reasons: [.containerUnsupported], nativeSafe: false, requiresVLC: false, risk: .medium)
        }

        switch container {
        case "mp4", "m4v", "mov", "fmp4":
            return ContainerResult(reasons: [.containerAppleNative], nativeSafe: true, requiresVLC: false, risk: .none)
        case "ts", "mpegts", "m2ts":
            // TS is native-safe for HLS but raw TS is risky
            return ContainerResult(reasons: [.containerTS], nativeSafe: true, requiresVLC: false, risk: .low)
        case "mkv", "matroska":
            return ContainerResult(reasons: [.containerMKV], nativeSafe: false, requiresVLC: true, risk: .high)
        case "webm":
            return ContainerResult(reasons: [.containerWebM], nativeSafe: false, requiresVLC: true, risk: .high)
        case "avi":
            return ContainerResult(reasons: [.containerAVI], nativeSafe: false, requiresVLC: true, risk: .high)
        default:
            return ContainerResult(reasons: [.containerUnsupported], nativeSafe: false, requiresVLC: true, risk: .high)
        }
    }

    // MARK: - Video Codec Evaluation

    private struct VideoResult {
        let reasons: [ReasonCode]
        let nativeSafe: Bool
        let requiresVLC: Bool
        let risk: RiskLevel
    }

    private func evaluateVideoCodec(_ codec: String?, bitDepth: Int?) -> VideoResult {
        guard let codec = codec?.lowercased(), !codec.isEmpty else {
            return VideoResult(reasons: [.videoUnsupported], nativeSafe: false, requiresVLC: false, risk: .medium)
        }

        if codec.contains("h264") || codec.contains("avc") {
            return VideoResult(reasons: [.videoH264Native], nativeSafe: true, requiresVLC: false, risk: .none)
        }
        if codec.contains("hevc") || codec.contains("h265") || codec.contains("dvh1") || codec.contains("dvhe") {
            // HEVC with 10-bit is native-safe on A9+
            let risk: RiskLevel = (bitDepth ?? 8) > 10 ? .medium : .none
            return VideoResult(reasons: [.videoHEVCNative], nativeSafe: true, requiresVLC: false, risk: risk)
        }
        if codec.contains("av1") || codec.contains("av01") {
            // AV1 is native on A17 Pro+ / M3+. Risk on older hardware.
            return VideoResult(reasons: [.videoAV1Native], nativeSafe: true, requiresVLC: false, risk: .low)
        }
        if codec.contains("vp9") || codec.contains("vp09") {
            return VideoResult(reasons: [.videoVP9RequiresVLC], nativeSafe: false, requiresVLC: true, risk: .none)
        }
        if codec.contains("mpeg2") || codec.contains("mp2v") {
            return VideoResult(reasons: [.videoMPEG2RequiresVLC], nativeSafe: false, requiresVLC: true, risk: .none)
        }
        if codec.contains("vc1") || codec.contains("vc-1") || codec.contains("wvc1") {
            return VideoResult(reasons: [.videoVC1RequiresVLC], nativeSafe: false, requiresVLC: true, risk: .none)
        }

        return VideoResult(reasons: [.videoUnsupported], nativeSafe: false, requiresVLC: true, risk: .high)
    }

    // MARK: - Audio Codec Evaluation

    private struct AudioResult {
        let reasons: [ReasonCode]
        let nativeSafe: Bool
        let requiresVLC: Bool
        let risk: RiskLevel
    }

    private func evaluateAudioCodec(_ codec: String?) -> AudioResult {
        guard let codec = codec?.lowercased(), !codec.isEmpty else {
            return AudioResult(reasons: [.audioUnsupported], nativeSafe: true, requiresVLC: false, risk: .low)
        }

        if codec.contains("aac") {
            return AudioResult(reasons: [.audioAACNative], nativeSafe: true, requiresVLC: false, risk: .none)
        }
        if codec.contains("eac3") || codec.contains("ec3") || codec.contains("e-ac-3") {
            return AudioResult(reasons: [.audioEAC3Native], nativeSafe: true, requiresVLC: false, risk: .none)
        }
        if codec.contains("ac3") || codec.contains("a52") {
            return AudioResult(reasons: [.audioAC3Native], nativeSafe: true, requiresVLC: false, risk: .none)
        }
        if codec.contains("alac") {
            return AudioResult(reasons: [.audioALACNative], nativeSafe: true, requiresVLC: false, risk: .none)
        }
        if codec.contains("flac") {
            return AudioResult(reasons: [.audioFLACNative], nativeSafe: true, requiresVLC: false, risk: .none)
        }
        if codec.contains("opus") {
            // Opus is native in CAF/MP4 containers on iOS 16+
            return AudioResult(reasons: [.audioOpusNative], nativeSafe: true, requiresVLC: false, risk: .low)
        }
        if codec.contains("mp3") || codec.contains("mp2") {
            return AudioResult(reasons: [.audioAACNative], nativeSafe: true, requiresVLC: false, risk: .none)
        }
        if codec.contains("pcm") || codec.contains("lpcm") {
            return AudioResult(reasons: [.audioAACNative], nativeSafe: true, requiresVLC: false, risk: .none)
        }
        if codec.contains("dts") && !codec.contains("hd") && !codec.contains("ma") {
            return AudioResult(reasons: [.audioDTSRequiresVLC], nativeSafe: false, requiresVLC: true, risk: .none)
        }
        if codec.contains("dts-hd") || codec.contains("dtshd") || codec.contains("dts-ma") {
            return AudioResult(reasons: [.audioDTSHDRequiresVLC], nativeSafe: false, requiresVLC: true, risk: .none)
        }
        if codec.contains("truehd") || codec.contains("mlp") {
            return AudioResult(reasons: [.audioTrueHDRequiresVLC], nativeSafe: false, requiresVLC: true, risk: .none)
        }
        if codec.contains("vorbis") {
            return AudioResult(reasons: [.audioVorbisRequiresVLC], nativeSafe: false, requiresVLC: true, risk: .none)
        }

        return AudioResult(reasons: [.audioUnsupported], nativeSafe: false, requiresVLC: false, risk: .medium)
    }

    // MARK: - Subtitle Evaluation

    private struct SubtitleResult {
        let reasons: [ReasonCode]
        let prefersVLC: Bool
        let risk: RiskLevel
    }

    private func evaluateSubtitles(_ codecs: [String]) -> SubtitleResult {
        guard !codecs.isEmpty else {
            return SubtitleResult(reasons: [], prefersVLC: false, risk: .none)
        }

        var reasons: [ReasonCode] = []
        var prefersVLC = false
        var maxRisk: RiskLevel = .none

        for codec in codecs {
            let lower = codec.lowercased()
            if lower.contains("srt") || lower.contains("subrip") {
                reasons.append(.subtitleSRTNative)
            } else if lower.contains("webvtt") || lower.contains("vtt") {
                reasons.append(.subtitleWebVTTNative)
            } else if lower.contains("ass") || lower.contains("ssa") {
                reasons.append(.subtitleASSRequiresVLC)
                prefersVLC = true
                maxRisk = max(maxRisk, .medium)
            } else if lower.contains("pgs") || lower.contains("hdmv") || lower.contains("pgssub") {
                reasons.append(.subtitlePGSRequiresVLC)
                prefersVLC = true
                maxRisk = max(maxRisk, .high)
            } else if lower.contains("vobsub") || lower.contains("dvd_subtitle") || lower.contains("dvdsub") {
                reasons.append(.subtitleVobSubRequiresVLC)
                prefersVLC = true
                maxRisk = max(maxRisk, .high)
            }
        }

        return SubtitleResult(reasons: reasons, prefersVLC: prefersVLC, risk: maxRisk)
    }

    // MARK: - HDR Evaluation

    private struct HDRResult {
        let reasons: [ReasonCode]
        let expectation: HDRExpectation
    }

    private func evaluateHDR(_ media: MediaCharacteristics) -> HDRResult {
        let range = media.videoRangeType?.lowercased() ?? media.videoRange?.lowercased() ?? ""

        if media.dvProfile != nil {
            return HDRResult(reasons: [.dolbyVisionNativePreserved], expectation: .dolbyVision)
        }
        if range.contains("hdr10") || range.contains("hdr") {
            return HDRResult(reasons: [.hdrNativePreserved], expectation: .hdr10)
        }
        if range.contains("hlg") {
            return HDRResult(reasons: [.hdrNativePreserved], expectation: .hlg)
        }
        return HDRResult(reasons: [.hdrNotApplicable], expectation: .sdr)
    }

    // MARK: - Source Reason

    private func sourceReason(for type: SourceType) -> ReasonCode {
        switch type {
        case .directPlay: return .sourceDirectPlay
        case .hls: return .sourceHLS
        case .progressive: return .sourceProgressive
        case .remux: return .sourceRemux
        case .transcode: return .sourceTranscode
        case .directStream: return .sourceDirectPlay
        case .unknown: return .sourceDirectPlay
        }
    }
}
