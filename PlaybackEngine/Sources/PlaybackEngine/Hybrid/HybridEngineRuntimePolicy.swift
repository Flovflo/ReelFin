import Foundation

public enum HybridEngineRuntimePolicy {
    public static func normalize(
        _ decision: EngineCapabilityDecision,
        vlcAvailable: Bool
    ) -> EngineCapabilityDecision {
        guard !vlcAvailable, decision.recommendation == .vlcRequired else {
            return decision
        }

        var reasons = decision.reasons.filter { $0 != .hdrDegradedByVLCFallback }
        if !reasons.contains(.fallbackToServerTranscode) {
            reasons.append(.fallbackToServerTranscode)
        }

        return EngineCapabilityDecision(
            recommendation: .serverTranscodePreferred,
            reasons: deduplicated(reasons),
            startupRisk: decision.startupRisk,
            subtitleRisk: decision.subtitleRisk,
            audioRisk: decision.audioRisk,
            hdrExpectation: normalizedHDRExpectation(from: decision.hdrExpectation),
            estimatedFeatureCompleteness: max(decision.estimatedFeatureCompleteness, 0.9)
        )
    }

    public static func resolveEngine(
        for decision: EngineCapabilityDecision,
        vlcAvailable: Bool
    ) -> PlaybackEngineType {
        guard vlcAvailable else {
            return .native
        }

        switch decision.recommendation {
        case .vlcRequired:
            return .vlc
        case .nativePreferred,
             .nativeAllowedButRisky,
             .nativeThenFallbackIfStartupFails,
             .serverTranscodePreferred,
             .unsupported:
            return .native
        }
    }

    private static func normalizedHDRExpectation(from expectation: HDRExpectation) -> HDRExpectation {
        guard expectation == .hdrDegradedByEngine else {
            return expectation
        }
        return .unknown
    }

    private static func deduplicated(_ reasons: [ReasonCode]) -> [ReasonCode] {
        var seen = Set<ReasonCode>()
        return reasons.filter { seen.insert($0).inserted }
    }
}
