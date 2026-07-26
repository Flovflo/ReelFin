@testable import ReelFinUI
import XCTest

final class ShimmerAnimationPolicyTests: XCTestCase {
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
}
