import XCTest
@testable import ReelFinUI

final class TVUXPolishNavigationTests: XCTestCase {
    func testHomeDetailCarouselKeepsOriginalRowForItemDuplicatedAcrossRails() throws {
        let context = TVHomeDetailPresentationContext(
            origin: .row(id: "second-row"),
            presentedItemIDs: ["before", "duplicate", "after"]
        )

        let target = try XCTUnwrap(
            TVHomeDetailReturnTargetResolver.resolve(
                context: context,
                displayedItemID: "duplicate",
                featuredItemIDs: ["duplicate"],
                rowItemIDsByID: [
                    "first-row": ["duplicate", "other"],
                    "second-row": ["before", "duplicate", "after"]
                ]
            )
        )

        XCTAssertEqual(target.origin, .row(id: "second-row"))
        XCTAssertEqual(target.displayedItemID, "duplicate")
        XCTAssertEqual(target.itemID, "duplicate")
        XCTAssertEqual(
            target.focusTargetID,
            HomeCardTransitionSource.id(rowID: "second-row", itemID: "duplicate")
        )
    }

    func testHomeDetailCarouselUsesHeroOnlyForHeroPresentationOrigin() throws {
        let context = TVHomeDetailPresentationContext(
            origin: .featured,
            presentedItemIDs: ["hero-start", "duplicate"]
        )

        let target = try XCTUnwrap(
            TVHomeDetailReturnTargetResolver.resolve(
                context: context,
                displayedItemID: "duplicate",
                featuredItemIDs: ["hero-start", "duplicate"],
                rowItemIDsByID: ["row": ["duplicate"]]
            )
        )

        XCTAssertEqual(target.origin, .featured)
        XCTAssertEqual(target.itemID, "duplicate")
        XCTAssertNil(target.focusTargetID)
    }

    func testHomeDetailCarouselFallsBackToNearestSurvivorInOriginalRow() throws {
        let context = TVHomeDetailPresentationContext(
            origin: .row(id: "origin-row"),
            presentedItemIDs: ["first", "second", "removed", "nearest"]
        )

        let target = try XCTUnwrap(
            TVHomeDetailReturnTargetResolver.resolve(
                context: context,
                displayedItemID: "removed",
                featuredItemIDs: ["removed"],
                rowItemIDsByID: [
                    "other-row": ["removed"],
                    "origin-row": ["first", "nearest"]
                ]
            )
        )

        XCTAssertEqual(target.origin, .row(id: "origin-row"))
        XCTAssertEqual(target.displayedItemID, "removed")
        XCTAssertEqual(target.itemID, "nearest")
        XCTAssertEqual(
            target.focusTargetID,
            HomeCardTransitionSource.id(rowID: "origin-row", itemID: "nearest")
        )
    }

    func testDetailBackIsConsumedUntilClosingCompletes() {
        var state = TVDetailPresentationCoordinator()
        state.beginOpening(itemID: "dexter", sourceID: "home-row-dexter")
        state.finishOpening()

        XCTAssertEqual(state.handleBack(), .beginClosing)
        XCTAssertEqual(state.handleBack(), .consumedWhileClosing)
        XCTAssertTrue(state.keepsDetailMounted)

        state.finishClosing()

        XCTAssertEqual(state.phase, .idle)
    }

    func testBackPrecedenceReturnsInsideAppBeforeSystemExit() {
        XCTAssertEqual(TVBackNavigationPolicy.action(for: .resumeChoice), .cancelResumeChoice)
        XCTAssertEqual(TVBackNavigationPolicy.action(for: .playerPanel), .closePlayerPanel)
        XCTAssertEqual(TVBackNavigationPolicy.action(for: .player), .closePlayer)
        XCTAssertEqual(TVBackNavigationPolicy.action(for: .detail), .closeDetail)
        XCTAssertEqual(TVBackNavigationPolicy.action(for: .root), .allowSystemExit)
    }

    func testInvalidPresentationTransitionsAreIgnored() {
        var state = TVDetailPresentationCoordinator()

        state.finishOpening()
        state.finishClosing()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.handleBack(), .allowRoot)

        state.beginOpening(itemID: "dexter", sourceID: nil)
        state.beginOpening(itemID: "other", sourceID: "other-source")
        XCTAssertEqual(state.phase, .opening(itemID: "dexter", sourceID: nil))

        state.finishClosing()
        XCTAssertEqual(state.phase, .opening(itemID: "dexter", sourceID: nil))
    }

    func testDetailTransitionMetricsUseSpecifiedDurations() {
        XCTAssertEqual(TVDetailTransitionMetrics.openingDuration, 0.34)
        XCTAssertEqual(TVDetailTransitionMetrics.closingDuration, 0.30)
        XCTAssertEqual(TVDetailTransitionMetrics.reducedMotionDuration, 0.18)
    }

    func testDetailDismissalUsesExplicitCallbackExactlyOnce() {
        var explicitCount = 0
        var fallbackCount = 0

        TVDetailDismissalRouter.request(
            explicit: { explicitCount += 1 },
            fallback: { fallbackCount += 1 }
        )

        XCTAssertEqual(explicitCount, 1)
        XCTAssertEqual(fallbackCount, 0)
    }

    func testDetailDismissalFallsBackWhenExplicitCallbackIsNil() {
        var fallbackCount = 0

        TVDetailDismissalRouter.request(
            explicit: nil,
            fallback: { fallbackCount += 1 }
        )

        XCTAssertEqual(fallbackCount, 1)
    }

    func testStaleHomeFocusHandoffCannotWin() {
        var coordinator = TVHomeFocusHandoffCoordinator()
        let stale = coordinator.begin(targetID: "old-card")
        let latest = coordinator.begin(targetID: "new-card")

        XCTAssertFalse(coordinator.owns(stale))
        XCTAssertTrue(coordinator.owns(latest))

        coordinator.cancel()

        XCTAssertFalse(coordinator.owns(latest))
    }

    func testUserFocusChangeInvalidatesRestoreBeforeStaleCompletionCanApply() {
        var coordinator = TVHomeFocusHandoffCoordinator()
        let restore = coordinator.begin(targetID: "return-card")

        coordinator.userFocusDidChange()

        XCTAssertFalse(coordinator.owns(restore))
        XCTAssertNil(coordinator.consume(restore))
    }

    func testTVDetailHostsUseCoordinatorTimingsWithoutNestedViewModelAnimations() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let home = try String(
            contentsOf: root.appendingPathComponent("ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift"),
            encoding: .utf8
        )
        let library = try String(
            contentsOf: root.appendingPathComponent("ReelFinUI/Sources/ReelFinUI/Library/LibraryView.swift"),
            encoding: .utf8
        )

        for source in [home, library] {
            XCTAssertTrue(source.contains("withAnimation(tvDetailOpenAnimation, completionCriteria: .logicallyComplete)"))
            XCTAssertTrue(source.contains("withAnimation(tvDetailCloseAnimation, completionCriteria: .logicallyComplete)"))
            XCTAssertTrue(source.contains("viewModel.select(item: item, animated: false)"))
            XCTAssertTrue(source.contains("viewModel.dismissDetail(animated: false)"))
            XCTAssertTrue(source.contains("detailPresentationVisualState == .presented"))
            XCTAssertFalse(source.contains(".animation(tvDetailOpenAnimation, value: detailPresentation.keepsDetailMounted)"))
        }
    }

    func testHomeFocusRestoreUsesCancelableOwnedHandoff() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let home = try String(
            contentsOf: root.appendingPathComponent("ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(home.contains("Task.sleep(nanoseconds: 220_000_000)"))
        XCTAssertTrue(home.contains("let request = beginHomeFocusHandoff("))
        XCTAssertTrue(home.contains("completeHomeFocusHandoff(request)"))
        XCTAssertTrue(home.contains("guard homeFocusHandoff.owns(request) else { return }"))
        XCTAssertTrue(home.contains(".onChange(of: focusedHomeItemID)"))
        XCTAssertTrue(home.contains("guard homeReturnTarget?.displayedItemID != item.id else { return }"))
        XCTAssertFalse(home.contains("guard oldValue != newValue, homeFocusHandoff.hasPendingRequest else { return }"))
        XCTAssertFalse(home.contains("guard newValue != featuredPrimaryActionFocusID else { return }"))
        XCTAssertTrue(home.contains("TVHomeItemFocusModifier(itemID: transitionSourceID"))
        XCTAssertTrue(home.contains("targetID: focusTargetID"))
        XCTAssertFalse(home.contains("viewModel.rowIDByItemID[item.id]"))
        XCTAssertTrue(home.contains("TVHomeFocusTransitionAccessibilityMarker("))
        XCTAssertTrue(home.contains("identifier: \"tv_home_focus_transition_count\""))
        XCTAssertTrue(home.contains("homeFocusTransitionCounter.recordChange(from: oldValue, to: newValue)"))
        XCTAssertTrue(home.contains("if TVLiveUIAutomationPolicy.isHomeFocusEvidenceEnabledForCurrentProcess {\n                homeFocusTransitionCounter.recordChange"))
        XCTAssertTrue(home.contains(".onMoveCommand { _ in"))
        XCTAssertTrue(home.contains("homeFocusHandoff.userFocusDidChange()"))
        XCTAssertTrue(home.contains("guard let targetID = homeFocusHandoff.consume(request) else { return }"))
        XCTAssertTrue(home.contains("homeFocusHandoffTask?.cancel()"))
    }

    func testLibraryKeepsTopRowFocusRouteAndExactDetailReturnProvenance() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let library = try String(
            contentsOf: root.appendingPathComponent(
                "ReelFinUI/Sources/ReelFinUI/Library/LibraryView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(library.contains(".focused($focusedLibraryItemID, equals: item.id)"))
        XCTAssertTrue(
            library.contains(
                "onMoveUp: topRowItemIDs.contains(item.id) ? focusPreferredControlBar : nil"
            )
        )
        XCTAssertTrue(
            library.contains(
                "transitionSourceID: LibraryCardTransitionSource.id(itemID: item.id)"
            )
        )
        XCTAssertTrue(library.contains("savedSelectedPosterID = item.id"))
        XCTAssertTrue(library.contains("focusedLibraryItemID = returnPosterID"))
    }

    func testDetailScrollCompletionIsEventDrivenAndStaleSafe() throws {
        let detail = try detailSource()

        XCTAssertFalse(detail.contains("Task.sleep(nanoseconds: 320_000_000)"))
        XCTAssertTrue(
            detail.contains(
                "withAnimation(.easeInOut(duration: 0.28), completionCriteria: .logicallyComplete)"
            )
        )
        XCTAssertTrue(detail.contains("guard tvScrollRequest == request else { return }"))
        XCTAssertTrue(detail.contains("onScrollRequestCompleted(request)"))
    }

    func testDetailKeepsOccurrenceQualifiedTransitionAndDisplayedReturnIdentity() throws {
        let detail = try detailSource()

        XCTAssertTrue(detail.contains("transitionSourceID.hasSuffix(\"::\\(currentReturnSourceItem.id)\")"))
        XCTAssertTrue(detail.contains("onDisplayedSourceItemChange?(currentReturnSourceItem)"))
        XCTAssertTrue(detail.contains("entry.id == currentItemID"))
        XCTAssertEqual(
            HomeCardTransitionSource.id(
                rowID: "continue-watching",
                itemID: "episode-1",
                occurrenceID: "cycle-2-index-0"
            ),
            "continue-watching::cycle-2-index-0::episode-1"
        )
        XCTAssertEqual(
            LibraryCardTransitionSource.id(itemID: "movie-1"),
            "library::movie-1"
        )
    }

    func testDetailGlassOwnsCompleteControlLabelsInsteadOfDetachedBackgrounds() throws {
        let detail = try detailSource()
        let detachedMaterialBackgrounds = [
            ".background { backgroundSurface }",
            ".background { primaryButtonBackground }",
            ".background { secondaryGlassBackground }",
            ".background { buttonBackground }",
        ]

        for detachedMaterialBackground in detachedMaterialBackgrounds {
            XCTAssertFalse(
                detail.contains(detachedMaterialBackground),
                "Glass attached to a detached background can composite above and erase its label."
            )
        }

        XCTAssertGreaterThanOrEqual(
            detail.components(separatedBy: "completeControlSurface {").count - 1,
            8,
            "Every iOS/tvOS Detail action surface should wrap its complete laid-out label."
        )
    }

    func testDetailWiresArtworkAndPrimaryActionPoliciesIntoRenderedViews() throws {
        let detail = try detailSource()

        XCTAssertTrue(
            detail.contains("DetailArtworkCostPolicy.composition(isSelected: isSelected)")
        )
        XCTAssertTrue(
            detail.contains("ForEach(TVDetailFocusTopology.primaryActionOrder, id: \\.self)")
        )
    }

    func testIOSDetailPrimaryActionsFollowEditorialOrder() throws {
        let detail = try detailSource()
        let identityBlock = try sourceSection(
            in: detail,
            from: "private var identityBlock: some View",
            to: "@ViewBuilder\n    private var resumeProgressBlock"
        )
        let play = try XCTUnwrap(identityBlock.range(of: "detail_primary_play_button"))
        let favorite = try XCTUnwrap(identityBlock.range(of: "detail_favorite_button"))
        let watched = try XCTUnwrap(identityBlock.range(of: "detail_watched_button"))

        XCTAssertLessThan(play.lowerBound, favorite.lowerBound)
        XCTAssertLessThan(favorite.lowerBound, watched.lowerBound)
    }

    func testIOSDetailScrollPresentationIsObservedOnlyByTopStageAndChrome() throws {
        let detail = try detailSource()

        XCTAssertFalse(
            detail.contains("@State private var scrollPresentation = IOSDetailScrollPresentation.expanded")
        )
        XCTAssertTrue(detail.contains("@Observable\nprivate final class IOSDetailScrollPresentationStore"))
        XCTAssertTrue(detail.contains("private struct IOSDetailTopStage"))
        XCTAssertTrue(detail.contains("private struct IOSDetailCompactHeader"))
    }

    func testIOSDetailCompactHeaderDestroysLiveBlurForReduceTransparency() throws {
        let detail = try detailSource()
        let compactHeader = try sourceSection(
            in: detail,
            from: "private struct IOSDetailCompactHeader",
            to: "private struct IOSDetailTopStage"
        )

        XCTAssertTrue(
            compactHeader.contains("@Environment(\\.accessibilityReduceTransparency)")
        )
        XCTAssertTrue(compactHeader.contains("if reduceTransparency"))
        XCTAssertTrue(compactHeader.contains("TransparentBlurView(style: .systemUltraThinMaterial)"))
    }

    func testDetailIdentitySpeaksVisibleKickerTitleAndMetadata() throws {
        let identity = try identitySource()

        XCTAssertTrue(identity.contains("EditorialMediaIdentityAccessibility.label("))
        XCTAssertFalse(identity.contains(".accessibilityLabel(item.name)"))
    }

    func testDetailMetadataDoesNotRepeatTheMediaTypeKicker() throws {
        let detail = try detailSource()
        let subtitle = try sourceSection(
            in: detail,
            from: "private var subtitleText: String",
            to: "private var mediaKicker: String"
        )

        for duplicatedType in ["TV Show", "Movie", "Episode", "Season"] {
            XCTAssertFalse(subtitle.contains("values.append(\"\(duplicatedType)\")"))
        }
    }

    func testStaticCastAndNeighborArtworkRemainNonInteractiveAndDecorative() throws {
        let detail = try detailSource()
        let castItem = try sourceSection(
            in: detail,
            from: "private struct TVCastRowItem",
            to: "private struct CastAvatarView"
        )
        let carouselCard = try sourceSection(
            in: detail,
            from: "private struct IOSDetailTopCarouselCard",
            to: "private enum HeroMetadataLayout"
        )

        for forbiddenFocusWork in ["@FocusState", ".focusable(", ".onMoveCommand", ".scaleEffect("] {
            XCTAssertFalse(castItem.contains(forbiddenFocusWork))
        }
        XCTAssertTrue(detail.contains("TVDetailFocusTopology.hasFocusableContentBeforeMoreLikeThis("))
        XCTAssertTrue(carouselCard.contains(".accessibilityHidden(true)"))
    }

    private func detailSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(
                "ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift"
            ),
            encoding: .utf8
        )
    }

    private func identitySource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(
                "ReelFinUI/Sources/ReelFinUI/Components/EditorialMediaIdentityView.swift"
            ),
            encoding: .utf8
        )
    }

    private func sourceSection(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return source[start..<end]
    }
}
