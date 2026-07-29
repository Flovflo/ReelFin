import CoreGraphics
@testable import ReelFinUI
import XCTest

final class LibraryEditorialLayoutTests: XCTestCase {
    func testStickyHeaderOffsetsInsideOneBucketResolveToOnePresentation() {
        let first = StickyBlurHeaderScrollPresentation.resolve(
            offset: 121,
            revealDistance: 160
        )
        let second = StickyBlurHeaderScrollPresentation.resolve(
            offset: 126,
            revealDistance: 160
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.step, 18)
        XCTAssertEqual(first.bucketCount, 24)
        XCTAssertEqual(first.progress, 0.75)
    }

    func testLibraryHeaderBecomesCompactAtStepEighteenOnly() {
        let beforeThreshold = StickyBlurHeaderScrollPresentation.resolve(
            offset: 119.999,
            revealDistance: LibraryHeaderPresentation.revealDistance
        )
        let atThreshold = StickyBlurHeaderScrollPresentation.resolve(
            offset: 120,
            revealDistance: LibraryHeaderPresentation.revealDistance
        )

        XCTAssertEqual(beforeThreshold.step, 17)
        XCTAssertEqual(atThreshold.step, 18)
        XCTAssertEqual(
            LibraryHeaderPresentation.resolve(
                quantizedRevealProgress: beforeThreshold.progress
            ),
            .expanded
        )
        XCTAssertEqual(
            LibraryHeaderPresentation.resolve(
                quantizedRevealProgress: atThreshold.progress
            ),
            .compact
        )
        XCTAssertEqual(LibraryHeaderPresentation.compactRevealThreshold, 0.75)
    }

    func testLibraryHeaderCrossfadeNeverShowsTwoFullyOpaqueControlClusters() {
        let expanded = LibraryHeaderTransition.resolve(revealProgress: 0)
        let midpoint = LibraryHeaderTransition.resolve(revealProgress: 0.70)
        let compact = LibraryHeaderTransition.resolve(revealProgress: 1)

        XCTAssertEqual(expanded.expandedControlsOpacity, 1)
        XCTAssertEqual(expanded.compactHeaderOpacity, 0)
        XCTAssertEqual(midpoint.expandedControlsOpacity, 0.5, accuracy: 0.001)
        XCTAssertEqual(midpoint.compactHeaderOpacity, 0.5, accuracy: 0.001)
        XCTAssertEqual(compact.expandedControlsOpacity, 0)
        XCTAssertEqual(compact.compactHeaderOpacity, 1)

        for step in 0 ... 24 {
            let state = LibraryHeaderTransition.resolve(
                revealProgress: CGFloat(step) / 24
            )
            XCTAssertEqual(
                state.expandedControlsOpacity + state.compactHeaderOpacity,
                1,
                accuracy: 0.001
            )
            XCTAssertFalse(
                state.expandedControlsAreInteractive && state.compactHeaderIsInteractive
            )
        }
    }

    func testReduceTransparencyFallbackIsFullyOpaqueOnlyWhenCompactControlsActivate() {
        XCTAssertEqual(
            EditorialOpaqueHeaderPolicy.opacity(
                revealProgress: 17.0 / 24.0,
                activationThreshold: LibraryHeaderPresentation.compactRevealThreshold
            ),
            0
        )
        XCTAssertEqual(
            EditorialOpaqueHeaderPolicy.opacity(
                revealProgress: 18.0 / 24.0,
                activationThreshold: LibraryHeaderPresentation.compactRevealThreshold
            ),
            1
        )
        XCTAssertEqual(
            EditorialOpaqueHeaderPolicy.opacity(
                revealProgress: 1,
                activationThreshold: LibraryHeaderPresentation.compactRevealThreshold
            ),
            1
        )
    }

    func testStickyHeaderKeepsActiveControlBandOpaqueBeforeFadingBelowIt() throws {
        let source = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Components/StickyBlurHeader.swift"
        )

        XCTAssertTrue(source.contains("opaqueFallbackRevealThreshold"))
        XCTAssertTrue(source.contains("frame(height: headerHeight)"))
        XCTAssertTrue(source.contains("EditorialOpaqueHeaderPolicy.opacity"))
        XCTAssertFalse(source.contains(".fill(ReelFinTheme.editorialOpaqueFallback)\n                .mask { blurMask }"))
    }

    func testAlwaysVisibleStickyHeaderDoesNotRequestScrollTracking() {
        XCTAssertFalse(StickyBlurHeaderVisibility.always.requiresScrollTracking)
        XCTAssertTrue(
            StickyBlurHeaderVisibility.revealOnScroll(
                distance: 160,
                minimumEffectOpacity: 0
            )
            .requiresScrollTracking
        )
    }

    func testTVLibraryActivationRunsActionSynchronously() {
        var events = ["before"]

        TVLibraryActivationPolicy.activate {
            events.append("activation")
        }
        events.append("after")

        XCTAssertEqual(events, ["before", "activation", "after"])
    }

    func testTVLibraryPosterCardWiresImmediatePolicyWithoutASleep() throws {
        let source = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Library/TVLibraryPosterCard.swift"
        )

        XCTAssertFalse(source.contains("Task.sleep"))
        XCTAssertTrue(source.contains("TVLibraryActivationPolicy.activate"))
        XCTAssertTrue(source.contains("onSelect(item)"))
    }

    func testLibraryGridAndTopRowResolverShareFullHDMetrics() throws {
        let layout = TVLibraryGridMetrics.focusLayout(containerWidth: 1_920)

        XCTAssertEqual(layout.columnCount, 6)

        let source = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Library/LibraryView.swift"
        )
        XCTAssertTrue(
            source.contains("minimum: TVLibraryGridMetrics.minimumItemWidth")
        )
        XCTAssertTrue(
            source.contains("spacing: TVLibraryGridMetrics.interItemSpacing")
        )
        XCTAssertTrue(
            source.contains("TVLibraryGridMetrics.focusLayout(containerWidth: containerWidth)")
        )
    }

    func testResultContextDescribesVisibleGridWhileReplacementCriteriaIsPending() {
        XCTAssertEqual(
            LibraryResultContext.resolve(
                visibleItemCount: 48,
                isUpdating: true
            ),
            "48 titles visible · Updating"
        )
        XCTAssertEqual(
            LibraryResultContext.resolve(
                visibleItemCount: 1,
                isUpdating: false
            ),
            "1 title visible"
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
