import XCTest
@testable import ReelFinUI

final class TVUXPolishNavigationTests: XCTestCase {
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
        XCTAssertTrue(home.contains("guard homeReturnTarget?.itemID != item.id else { return }"))
        XCTAssertTrue(home.contains("guard newValue != featuredPrimaryActionFocusID else { return }"))
        XCTAssertTrue(home.contains("TVHomeItemFocusModifier(itemID: transitionSourceID"))
        XCTAssertTrue(home.contains("targetID: HomeCardTransitionSource.id(rowID: rowID, itemID: itemID)"))
        XCTAssertTrue(home.contains("TVHomeFocusTransitionAccessibilityMarker("))
        XCTAssertTrue(home.contains("identifier: \"tv_home_focus_transition_count\""))
        XCTAssertTrue(home.contains("homeFocusTransitionCounter.recordChange(from: oldValue, to: newValue)"))
        XCTAssertTrue(home.contains("if TVLiveUIAutomationPolicy.isHomeFocusEvidenceEnabledForCurrentProcess {\n                homeFocusTransitionCounter.recordChange"))
        XCTAssertTrue(home.contains(".onMoveCommand { _ in"))
        XCTAssertTrue(home.contains("homeFocusHandoff.userFocusDidChange()"))
        XCTAssertTrue(home.contains("guard let targetID = homeFocusHandoff.consume(request) else { return }"))
        XCTAssertTrue(home.contains("homeFocusHandoffTask?.cancel()"))
    }
}
