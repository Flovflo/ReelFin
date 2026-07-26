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
