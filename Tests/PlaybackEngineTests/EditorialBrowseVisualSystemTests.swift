@testable import ReelFinUI
import XCTest

final class EditorialBrowseVisualSystemTests: XCTestCase {
    func testCompactHomeHeroUsesAContentFirstHeight() {
        XCTAssertEqual(
            HomeEditorialPresentationPolicy.iosHeroHeight(
                compact: true,
                accessibilitySize: false
            ),
            430
        )
        XCTAssertEqual(
            HomeEditorialPresentationPolicy.iosHeroHeight(
                compact: true,
                accessibilitySize: true
            ),
            520
        )
        XCTAssertEqual(
            HomeEditorialPresentationPolicy.iosHeroHeight(
                compact: false,
                accessibilitySize: false
            ),
            600
        )
    }

    func testHeroFallbackTitlePreservesReadableCaseAndAllowsThreeLines() throws {
        let source = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Components/EditorialMediaIdentityView.swift"
        )

        XCTAssertTrue(source.contains("Text(displayedFallbackTitle)"))
        XCTAssertTrue(source.contains("style == .iosHero ? fallbackTitle : fallbackTitle.uppercased()"))
        XCTAssertTrue(source.contains(".lineLimit(titleLineLimit)"))
    }

    func testCastAvatarAlwaysAttemptsArtworkAndKeepsItsMonogramAsFallback() throws {
        let source = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift"
        )

        XCTAssertFalse(source.contains("if person.primaryImageTag != nil"))
        XCTAssertTrue(source.contains("request: ArtworkRequest.make(for: avatarArtworkItem, role: .avatar)"))
        XCTAssertTrue(source.contains("showsPlaceholder: false"))
    }

    func testHomeHeroPrimaryActionNeverWrapsOnCompactPhones() throws {
        let source = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Components/HeroCarouselView.swift"
        )

        XCTAssertTrue(source.contains(
            "Text(primaryActionTitle(for: item))\n" +
                "                                .lineLimit(1)\n" +
                "                                .minimumScaleFactor(0.78)"
        ))
        XCTAssertTrue(source.contains(".layoutPriority(1)"))
    }

    func testHomeHeroGlassUsesCompleteControlSurfaces() throws {
        let source = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Components/HeroCarouselView.swift"
        )
        let home = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift"
        )

        XCTAssertTrue(source.contains("heroPlaySurface"))
        XCTAssertTrue(source.contains("heroCircleSurface"))
        XCTAssertTrue(source.contains("actionSurface"))
        XCTAssertTrue(home.contains("sectionChevronSurface"))
        XCTAssertFalse(source.contains(".background { heroPlayBackground }"))
        XCTAssertFalse(source.contains(".background { heroCircleBackground"))
        XCTAssertFalse(source.contains("private var heroPlayBackground"))
        XCTAssertFalse(source.contains(".background { backgroundView }"))
        XCTAssertFalse(home.contains(".background { sectionChevronBackground }"))
    }

    func testVisibleHomeArtworkUsesCanonicalPrefetchedRoles() throws {
        let hero = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Components/HeroCarouselView.swift"
        )
        let home = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift"
        )

        XCTAssertTrue(hero.contains("ArtworkRequest.make(for: item, role: .heroHigh)"))
        XCTAssertTrue(home.contains("ArtworkRequest.make(for: item, role: .landscapeRail)"))
        XCTAssertTrue(home.contains("ArtworkRequest.make(for: item, role: .heroHigh)"))
    }

    func testHomeOpaqueHeaderActivatesWithItsVisibleChrome() throws {
        XCTAssertEqual(HomeEditorialPresentationPolicy.stickyChromeRevealThreshold, 0.82)
        XCTAssertEqual(
            EditorialOpaqueHeaderPolicy.opacity(
                revealProgress: 0.81,
                activationThreshold: HomeEditorialPresentationPolicy.stickyChromeRevealThreshold
            ),
            0
        )
        XCTAssertEqual(
            EditorialOpaqueHeaderPolicy.opacity(
                revealProgress: 0.82,
                activationThreshold: HomeEditorialPresentationPolicy.stickyChromeRevealThreshold
            ),
            1
        )

        let home = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift"
        )
        XCTAssertTrue(home.contains("opaqueFallbackRevealThreshold: HomeEditorialPresentationPolicy.stickyChromeRevealThreshold"))
        XCTAssertTrue(home.contains("progress - HomeEditorialPresentationPolicy.stickyChromeRevealThreshold"))
    }

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

    func testHeroArtworkLoadsOnlyForActivePageAndStagesHighResolution() {
        XCTAssertEqual(
            HeroArtworkLoadingPolicy.layers(
                pageIndex: 0,
                currentIndex: 0,
                lowResolutionReady: false
            ),
            [.lowResolution, .logo]
        )
        XCTAssertEqual(
            HeroArtworkLoadingPolicy.layers(
                pageIndex: 0,
                currentIndex: 0,
                lowResolutionReady: true
            ),
            [.lowResolution, .highResolution, .logo]
        )
        XCTAssertEqual(
            HeroArtworkLoadingPolicy.layers(
                pageIndex: 1,
                currentIndex: 0,
                lowResolutionReady: true
            ),
            []
        )
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

    func testSelectedDetailArtworkCompositionUsesOneCanonicalTwoLayerHero() {
        let plan = DetailArtworkCostPolicy.composition(isSelected: true)

        XCTAssertEqual(plan.role, .hero)
        XCTAssertEqual(plan.heroStackCount, 1)
        XCTAssertEqual(plan.imageLayerCount, 2)
        XCTAssertEqual(plan.canonicalRoles, [.heroLow, .heroHigh])
    }

    func testNeighborDetailArtworkCompositionUsesOneCanonicalLandscapeImage() {
        let plan = DetailArtworkCostPolicy.composition(isSelected: false)

        XCTAssertEqual(plan.role, .preview)
        XCTAssertEqual(plan.heroStackCount, 0)
        XCTAssertEqual(plan.imageLayerCount, 1)
        XCTAssertEqual(plan.canonicalRoles, [.landscapeRail])
    }

    func testEditorialIdentityAccessibilitySpeaksAllVisibleContext() {
        XCTAssertEqual(
            EditorialMediaIdentityAccessibility.label(
                itemName: "Continue Series",
                kicker: " Series ",
                metadata: "Drama · Mystery"
            ),
            "Series, Continue Series, Drama · Mystery"
        )
        XCTAssertEqual(
            EditorialMediaIdentityAccessibility.label(
                itemName: "Sample Movie",
                kicker: nil,
                metadata: "  "
            ),
            "Sample Movie"
        )
    }

    func testEditorialIdentityAccessibilityIdentifierTracksSelectedMedia() {
        XCTAssertEqual(
            EditorialMediaIdentityAccessibility.identifier(itemID: "cw-movie-1"),
            "editorial_media_identity_cw-movie-1"
        )
    }

    private func sourceText(at path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
