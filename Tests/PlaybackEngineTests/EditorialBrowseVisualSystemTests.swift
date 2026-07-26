@testable import ReelFinUI
import XCTest

final class EditorialBrowseVisualSystemTests: XCTestCase {
    func testHeroRotationRequiresActiveUnassistedIdleMotion() {
        XCTAssertTrue(HeroRotationPolicy.allowsAutomaticAdvance(
            sceneIsActive: true,
            isUserInteracting: false,
            reduceMotion: false,
            voiceOverEnabled: false,
            itemCount: 2
        ))
        XCTAssertFalse(HeroRotationPolicy.allowsAutomaticAdvance(
            sceneIsActive: false,
            isUserInteracting: false,
            reduceMotion: false,
            voiceOverEnabled: false,
            itemCount: 2
        ))
        XCTAssertFalse(HeroRotationPolicy.allowsAutomaticAdvance(
            sceneIsActive: true,
            isUserInteracting: true,
            reduceMotion: false,
            voiceOverEnabled: false,
            itemCount: 2
        ))
        XCTAssertFalse(HeroRotationPolicy.allowsAutomaticAdvance(
            sceneIsActive: true,
            isUserInteracting: false,
            reduceMotion: true,
            voiceOverEnabled: false,
            itemCount: 2
        ))
        XCTAssertFalse(HeroRotationPolicy.allowsAutomaticAdvance(
            sceneIsActive: true,
            isUserInteracting: false,
            reduceMotion: false,
            voiceOverEnabled: true,
            itemCount: 2
        ))
    }

    func testHeroRotationNextIndexWrapsAndRejectsInvalidCollections() {
        XCTAssertEqual(HeroRotationPolicy.nextIndex(currentIndex: 0, itemCount: 3), 1)
        XCTAssertEqual(HeroRotationPolicy.nextIndex(currentIndex: 2, itemCount: 3), 0)
        XCTAssertNil(HeroRotationPolicy.nextIndex(currentIndex: 0, itemCount: 1))
        XCTAssertNil(HeroRotationPolicy.nextIndex(currentIndex: -1, itemCount: 3))
        XCTAssertNil(HeroRotationPolicy.nextIndex(currentIndex: 3, itemCount: 3))
    }

    func testHeroHapticsAreReservedForDirectPageChanges() {
        XCTAssertFalse(HeroRotationPolicy.allowsHaptic(for: .automatic))
        XCTAssertTrue(HeroRotationPolicy.allowsHaptic(for: .direct))
    }

    func testEditorialMotionAndGlassFallbacksAreAccessible() {
        XCTAssertEqual(EditorialMotion.heroPageDuration(reduceMotion: false), 0.21)
        XCTAssertEqual(EditorialMotion.heroPageDuration(reduceMotion: true), 0.18)
        XCTAssertEqual(EditorialMotion.focusScale(role: .libraryPoster, reduceMotion: true), 1.02)
        XCTAssertEqual(EditorialGlassRole.focusedMedia.presentation(reduceTransparency: true), .opaque)
        XCTAssertEqual(EditorialGlassRole.actionCluster.presentation(reduceTransparency: false), .interactiveGlass)
    }

    func testEditorialGlassRolesKeepRestingChromePassive() {
        XCTAssertEqual(EditorialGlassRole.navigation.presentation(reduceTransparency: false), .interactiveGlass)
        XCTAssertEqual(EditorialGlassRole.compactControl.presentation(reduceTransparency: false), .interactiveGlass)
        XCTAssertEqual(EditorialGlassRole.focusedMedia.presentation(reduceTransparency: false), .passiveGlass)
    }

    func testDetailArtworkPolicyUsesOneHeroAndCheapNeighbors() {
        XCTAssertEqual(DetailArtworkCostPolicy.role(isSelected: true), .hero)
        XCTAssertEqual(DetailArtworkCostPolicy.role(isSelected: false), .preview)
        XCTAssertEqual(DetailArtworkCostPolicy.heroLayerBudget(isSelected: true), 1)
        XCTAssertEqual(DetailArtworkCostPolicy.heroLayerBudget(isSelected: false), 0)
    }
}
