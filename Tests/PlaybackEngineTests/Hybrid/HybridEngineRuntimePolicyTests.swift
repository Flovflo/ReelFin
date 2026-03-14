import XCTest
@testable import PlaybackEngine

final class HybridEngineRuntimePolicyTests: XCTestCase {
    func testVLCRequiredWithoutVLCAvailabilityBecomesServerTranscodePreferred() {
        let decision = EngineCapabilityDecision(
            recommendation: .vlcRequired,
            reasons: [.containerMKV, .hdrDegradedByVLCFallback],
            hdrExpectation: .hdrDegradedByEngine,
            estimatedFeatureCompleteness: 0.85
        )

        let normalized = HybridEngineRuntimePolicy.normalize(decision, vlcAvailable: false)

        XCTAssertEqual(normalized.recommendation, .serverTranscodePreferred)
        XCTAssertTrue(normalized.reasons.contains(.containerMKV))
        XCTAssertTrue(normalized.reasons.contains(.fallbackToServerTranscode))
        XCTAssertFalse(normalized.reasons.contains(.hdrDegradedByVLCFallback))
        XCTAssertEqual(normalized.hdrExpectation, .unknown)
    }

    func testVLCRequiredWithVLCAvailabilityStaysVLCRequired() {
        let decision = EngineCapabilityDecision(recommendation: .vlcRequired, reasons: [.containerMKV])

        let normalized = HybridEngineRuntimePolicy.normalize(decision, vlcAvailable: true)

        XCTAssertEqual(normalized, decision)
        XCTAssertEqual(
            HybridEngineRuntimePolicy.resolveEngine(for: normalized, vlcAvailable: true),
            .vlc
        )
    }

    func testServerTranscodePreferredUsesNativeEngine() {
        let decision = EngineCapabilityDecision(
            recommendation: .serverTranscodePreferred,
            reasons: [.fallbackToServerTranscode]
        )

        XCTAssertEqual(
            HybridEngineRuntimePolicy.resolveEngine(for: decision, vlcAvailable: false),
            .native
        )
        XCTAssertEqual(
            HybridEngineRuntimePolicy.resolveEngine(for: decision, vlcAvailable: true),
            .native
        )
    }
}
