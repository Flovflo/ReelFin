import Shared
@testable import ReelFinUI
import XCTest

final class ShimmerAnimationPolicyTests: XCTestCase {
    func testOnlyLowResolutionHeroRequestsAnimateTheirPlaceholder() {
        XCTAssertTrue(
            ShimmerAnimationPolicy.animationEnabled(for: .heroBackdropLow)
        )

        for profile in ArtworkRequestProfile.allCases where profile != .heroBackdropLow {
            XCTAssertFalse(
                ShimmerAnimationPolicy.animationEnabled(for: profile),
                "Unexpected perpetual placeholder animation for \(profile)"
            )
        }
    }

    func testCachedRemoteImageWiresTheBoundedPlaceholderPolicy() throws {
        let source = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Components/CachedRemoteImage.swift"
        )

        XCTAssertTrue(source.contains("ShimmerView(animationEnabled: placeholderAnimationEnabled)"))
        XCTAssertTrue(source.contains("placeholderAnimationEnabled: Bool = false"))
        XCTAssertTrue(source.contains("ShimmerAnimationPolicy.animationEnabled("))
        XCTAssertTrue(source.contains("for: request.profile"))
        XCTAssertFalse(source.contains("ShimmerView()"))
    }

    func testDirectSkeletonShimmersAreStaticUnlessExplicitlyBudgeted() throws {
        let shimmer = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Components/ShimmerView.swift"
        )
        let home = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift"
        )
        let detail = try sourceText(
            at: "ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift"
        )

        XCTAssertTrue(shimmer.contains("public init(animationEnabled: Bool = false)"))
        XCTAssertFalse(home.contains("ShimmerView(animationEnabled: true)"))
        XCTAssertFalse(detail.contains("ShimmerView(animationEnabled: true)"))
    }

    func testAnimationRunsOnlyWhenEnabledAndReduceMotionIsOff() {
        XCTAssertEqual(
            ShimmerAnimationPolicy.branch(animationEnabled: true, reduceMotion: false),
            .animated
        )
    }

    func testDisabledAnimationUsesStaticBranch() {
        XCTAssertEqual(
            ShimmerAnimationPolicy.branch(animationEnabled: false, reduceMotion: false),
            .static
        )
    }

    func testReduceMotionUsesStaticBranch() {
        XCTAssertEqual(
            ShimmerAnimationPolicy.branch(animationEnabled: true, reduceMotion: true),
            .static
        )
    }

    func testAnimatedAndStaticBranchesHaveDistinctIdentities() {
        XCTAssertNotEqual(ShimmerAnimationBranch.animated.id, ShimmerAnimationBranch.static.id)
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
