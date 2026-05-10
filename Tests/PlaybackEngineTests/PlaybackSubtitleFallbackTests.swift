import PlaybackEngine
import Shared
import XCTest

final class PlaybackSubtitleFallbackTests: XCTestCase {
    func testSubtitleBurnInProtectionFlagsBitmapAndASSOn4KHDR() {
        let source = makeGuaranteeSource(container: "mkv", videoRangeType: "HDR10")
        let pgs = MediaTrack(id: "pgs", title: "English PGS", codec: "pgs", isDefault: true, index: 3)
        let ass = MediaTrack(id: "ass", title: "Signs ASS", codec: "ass", isDefault: false, index: 4)
        let srt = MediaTrack(id: "srt", title: "English SRT", codec: "srt", isDefault: false, index: 5)
        let policy = SubtitleCompatibilityPolicy()

        XCTAssertEqual(policy.qualityImpact(track: pgs, source: source), .requiresBurnIn)
        XCTAssertEqual(policy.qualityImpact(track: ass, source: source), .riskyStyledText)
        XCTAssertEqual(policy.qualityImpact(track: srt, source: source), .clientSideText)
        XCTAssertTrue(policy.shouldBlockSubtitleSelection(track: pgs, strictMode: false, sourceIsHDRorDV: true, sourceIs4K: true))
        XCTAssertTrue(policy.shouldBlockSubtitleSelection(track: ass, strictMode: false, sourceIsHDRorDV: true, sourceIs4K: true))
    }

    func testFallbackRecommendationForSubtitleBurnInPreservesOriginalChoice() {
        let source = makeGuaranteeSource(
            container: "mkv",
            videoRangeType: "DOVI",
            dvProfile: 5
        )
        let pgs = MediaTrack(id: "pgs", title: "English PGS", codec: "pgs", isDefault: true, index: 8)

        let recommendation = PlaybackFallbackRecommendationFactory.subtitleBurnInRecommendation(
            source: source,
            subtitleTrack: pgs
        )

        XCTAssertEqual(recommendation?.trigger, .subtitleBurnInRequired)
        XCTAssertEqual(recommendation?.options.first?.kind, .keepOriginal)
        XCTAssertEqual(recommendation?.options.first?.preservesDolbyVision, true)
        XCTAssertTrue(recommendation?.message.localizedCaseInsensitiveContains("requires video transcoding") == true)
    }
}
