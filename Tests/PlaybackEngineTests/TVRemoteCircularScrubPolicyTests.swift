import CoreGraphics
import XCTest
@testable import ReelFinUI

final class TVRemoteCircularScrubPolicyTests: XCTestCase {
    func testAngleUnwrapAcrossPiMovesForwardWithoutJump() throws {
        let previous = sample(angle: .pi - 0.1, timestamp: 0)
        let current = sample(angle: -.pi + 0.1, timestamp: 1)

        let delta = TVRemoteCircularScrubPolicy.angularDelta(previous: previous, current: current)

        XCTAssertEqual(try XCTUnwrap(delta), 0.2, accuracy: 0.000_001)
    }

    func testAngleUnwrapAcrossNegativePiMovesBackwardWithoutJump() throws {
        let previous = sample(angle: -.pi + 0.1, timestamp: 0)
        let current = sample(angle: .pi - 0.1, timestamp: 1)

        let delta = TVRemoteCircularScrubPolicy.angularDelta(previous: previous, current: current)

        XCTAssertEqual(try XCTUnwrap(delta), -0.2, accuracy: 0.000_001)
    }

    func testClockwiseAndCounterClockwiseHaveOppositeSigns() throws {
        let origin = sample(angle: 0, timestamp: 0)
        let clockwise = sample(angle: .pi / 2, timestamp: 1)
        let counterClockwise = sample(angle: -.pi / 2, timestamp: 1)

        let clockwiseDelta = try XCTUnwrap(
            TVRemoteCircularScrubPolicy.angularDelta(previous: origin, current: clockwise)
        )
        let counterClockwiseDelta = try XCTUnwrap(
            TVRemoteCircularScrubPolicy.angularDelta(previous: origin, current: counterClockwise)
        )

        XCTAssertEqual(clockwiseDelta, .pi / 2, accuracy: 0.000_001)
        XCTAssertEqual(counterClockwiseDelta, -.pi / 2, accuracy: 0.000_001)
        XCTAssertEqual(clockwiseDelta, -counterClockwiseDelta, accuracy: 0.000_001)
    }

    func testCenterDeadZoneIgnoresUnstableSamples() {
        let outside = sample(angle: 0, radius: 40, timestamp: 0)
        let inside = sample(angle: .pi / 2, radius: 17, timestamp: 1)

        XCTAssertNil(TVRemoteCircularScrubPolicy.angularDelta(previous: inside, current: outside))
        XCTAssertNil(TVRemoteCircularScrubPolicy.angularDelta(previous: outside, current: inside))
    }

    func testCenterDeadZoneBoundaryAtEighteenIsAccepted() throws {
        let previous = sample(angle: 0, radius: 18, timestamp: 0)
        let current = sample(angle: .pi / 2, radius: 18, timestamp: 1)

        let delta = TVRemoteCircularScrubPolicy.angularDelta(previous: previous, current: current)

        XCTAssertEqual(try XCTUnwrap(delta), .pi / 2, accuracy: 0.000_001)
    }

    func testSecondsPerRevolutionScalesAndClamps() {
        XCTAssertEqual(TVRemoteCircularScrubPolicy.secondsPerRevolution(duration: 900), 30)
        XCTAssertEqual(TVRemoteCircularScrubPolicy.secondsPerRevolution(duration: 1_800), 60)
        XCTAssertEqual(TVRemoteCircularScrubPolicy.secondsPerRevolution(duration: 9_000), 300)
        XCTAssertEqual(TVRemoteCircularScrubPolicy.secondsPerRevolution(duration: 14_400), 300)
        XCTAssertEqual(TVRemoteCircularScrubPolicy.secondsPerRevolution(duration: 60), 30)
        XCTAssertEqual(TVRemoteCircularScrubPolicy.secondsPerRevolution(duration: 100_000), 300)
    }

    func testVelocityMultiplierClampsBetweenHalfAndFour() {
        XCTAssertEqual(TVRemoteCircularScrubPolicy.velocityMultiplier(radiansPerSecond: 0.2), 0.5)
        XCTAssertEqual(TVRemoteCircularScrubPolicy.velocityMultiplier(radiansPerSecond: 0.6), 1)
        XCTAssertEqual(TVRemoteCircularScrubPolicy.velocityMultiplier(radiansPerSecond: -2.2), 2)
        XCTAssertEqual(TVRemoteCircularScrubPolicy.velocityMultiplier(radiansPerSecond: 4.0), 4)
        XCTAssertEqual(TVRemoteCircularScrubPolicy.velocityMultiplier(radiansPerSecond: 8), 4)
    }

    func testPolicyHelpersNeutralizeNonFiniteInputs() {
        let nonFiniteValues: [Double] = [.nan, .infinity, -.infinity]

        for value in nonFiniteValues {
            XCTAssertEqual(TVRemoteCircularScrubPolicy.secondsPerRevolution(duration: value), 30)
            XCTAssertEqual(TVRemoteCircularScrubPolicy.velocityMultiplier(radiansPerSecond: value), 1)

            let ignoredDeltaTarget = TVRemoteCircularScrubPolicy.target(
                original: 50,
                weightedRadians: value,
                duration: 100
            )
            XCTAssertEqual(ignoredDeltaTarget, 50)
            XCTAssertTrue(ignoredDeltaTarget.isFinite)

            let invalidOriginalTarget = TVRemoteCircularScrubPolicy.target(
                original: value,
                weightedRadians: 0,
                duration: 100
            )
            XCTAssertEqual(invalidOriginalTarget, 0)
            XCTAssertTrue(invalidOriginalTarget.isFinite)

            let invalidDurationTarget = TVRemoteCircularScrubPolicy.target(
                original: 50,
                weightedRadians: 0,
                duration: value
            )
            XCTAssertEqual(invalidDurationTarget, 0)
            XCTAssertTrue(invalidDurationTarget.isFinite)
        }

        XCTAssertEqual(
            TVRemoteCircularScrubPolicy.target(
                original: 50,
                weightedRadians: .greatestFiniteMagnitude,
                duration: 100
            ),
            100
        )

        let valid = sample(angle: 0, timestamp: 0)
        let invalidGeometry = TVRemoteScrubSample(
            location: CGPoint(x: CGFloat.nan, y: 100),
            center: CGPoint(x: 100, y: 100),
            timestamp: 1
        )
        let invalidTimestamp = sample(angle: .pi / 2, timestamp: .infinity)
        XCTAssertNil(TVRemoteCircularScrubPolicy.angularDelta(previous: valid, current: invalidGeometry))
        XCTAssertNil(TVRemoteCircularScrubPolicy.angularDelta(previous: valid, current: invalidTimestamp))
    }

    func testTargetClampsAtZeroAndDuration() {
        XCTAssertEqual(
            TVRemoteCircularScrubPolicy.target(
                original: 10,
                weightedRadians: -2 * .pi,
                duration: 100
            ),
            0
        )
        XCTAssertEqual(
            TVRemoteCircularScrubPolicy.target(
                original: 95,
                weightedRadians: 2 * .pi,
                duration: 100
            ),
            100
        )
    }

    func testCircularSessionPausesPreviewsThenCommitsOnce() throws {
        var session = TVRemoteCircularScrubSession()
        XCTAssertTrue(session.begin(
            sample: sample(angle: 0, timestamp: 0),
            originalTime: 300,
            duration: 1_800,
            wasPlaying: true
        ))

        let previewTarget = try XCTUnwrap(session.update(sample(angle: .pi / 2, timestamp: 1)))
        XCTAssertEqual(previewTarget, 315, accuracy: 0.000_001)

        let resolution = try XCTUnwrap(session.commit())
        XCTAssertEqual(resolution.targetSeconds, previewTarget, accuracy: 0.000_001)
        XCTAssertTrue(resolution.wasPlaying)
        XCTAssertNil(session.commit())
        XCTAssertNil(session.cancel())
    }

    func testCircularSessionCancelRestoresOriginalTimeAndIntent() throws {
        var session = TVRemoteCircularScrubSession()
        XCTAssertTrue(session.begin(
            sample: sample(angle: 0, timestamp: 0),
            originalTime: 400,
            duration: 1_800,
            wasPlaying: false
        ))
        XCTAssertNotNil(session.update(sample(angle: -.pi / 2, timestamp: 1)))

        let resolution = try XCTUnwrap(session.cancel())
        XCTAssertEqual(resolution.targetSeconds, 400)
        XCTAssertFalse(resolution.wasPlaying)
        XCTAssertNil(session.cancel())
        XCTAssertNil(session.commit())
    }

    func testCircularSessionCannotBeginWithoutFiniteDuration() {
        let start = sample(angle: 0, timestamp: 0)
        let invalidDurations: [Double] = [0, -1, .infinity, -.infinity, .nan]

        for duration in invalidDurations {
            var session = TVRemoteCircularScrubSession()
            XCTAssertFalse(session.begin(
                sample: start,
                originalTime: 10,
                duration: duration,
                wasPlaying: true
            ))
            XCTAssertNil(session.commit())
        }

        var session = TVRemoteCircularScrubSession()
        XCTAssertFalse(session.begin(
            sample: start,
            originalTime: .nan,
            duration: 100,
            wasPlaying: true
        ))
    }

    func testCircularSessionRejectsNonFiniteInitialSample() {
        let invalidSamples = [
            TVRemoteScrubSample(
                location: CGPoint(x: CGFloat.nan, y: 100),
                center: CGPoint(x: 100, y: 100),
                timestamp: 0
            ),
            TVRemoteScrubSample(
                location: CGPoint(x: CGFloat.infinity, y: 100),
                center: CGPoint(x: 100, y: 100),
                timestamp: 0
            ),
            sample(angle: 0, timestamp: .nan),
            sample(angle: 0, timestamp: .infinity),
            sample(angle: 0, timestamp: -.infinity)
        ]

        for invalidSample in invalidSamples {
            var session = TVRemoteCircularScrubSession()
            XCTAssertFalse(session.begin(
                sample: invalidSample,
                originalTime: 50,
                duration: 100,
                wasPlaying: true
            ))
            XCTAssertNil(session.commit())
        }
    }

    func testCircularSessionIgnoresNonFiniteAndNonMonotonicUpdates() throws {
        var session = TVRemoteCircularScrubSession()
        XCTAssertTrue(session.begin(
            sample: sample(angle: 0, timestamp: 10),
            originalTime: 300,
            duration: 1_800,
            wasPlaying: true
        ))

        let invalidUpdates = [
            sample(angle: .pi / 2, timestamp: .nan),
            sample(angle: .pi / 2, timestamp: .infinity),
            sample(angle: .pi / 2, timestamp: -.infinity),
            TVRemoteScrubSample(
                location: CGPoint(x: CGFloat.nan, y: 100),
                center: CGPoint(x: 100, y: 100),
                timestamp: 11
            ),
            TVRemoteScrubSample(
                location: CGPoint(x: CGFloat.infinity, y: 100),
                center: CGPoint(x: 100, y: 100),
                timestamp: 11
            ),
            sample(angle: .pi / 2, timestamp: 10),
            sample(angle: .pi / 2, timestamp: 9)
        ]

        for invalidUpdate in invalidUpdates {
            let target = try XCTUnwrap(session.update(invalidUpdate))
            XCTAssertEqual(target, 300)
            XCTAssertTrue(target.isFinite)
        }

        let validTarget = try XCTUnwrap(session.update(sample(angle: .pi / 2, timestamp: 11)))
        XCTAssertEqual(validTarget, 315, accuracy: 0.000_001)
        XCTAssertTrue(validTarget.isFinite)

        let resolution = try XCTUnwrap(session.commit())
        XCTAssertEqual(resolution.targetSeconds, validTarget, accuracy: 0.000_001)
        XCTAssertTrue(resolution.targetSeconds.isFinite)
    }

    func testCircularSessionUpdateIsLatestValueNotQueuedHistory() throws {
        var session = TVRemoteCircularScrubSession()
        XCTAssertTrue(session.begin(
            sample: sample(angle: 0, timestamp: 0),
            originalTime: 500,
            duration: 1_800,
            wasPlaying: true
        ))

        _ = session.update(sample(angle: .pi / 4, timestamp: 1))
        _ = session.update(sample(angle: .pi / 2, timestamp: 2))
        let latestTarget = try XCTUnwrap(session.update(sample(angle: .pi, timestamp: 3)))

        let resolution = try XCTUnwrap(session.commit())
        XCTAssertEqual(resolution.targetSeconds, latestTarget, accuracy: 0.000_001)
        XCTAssertNil(session.update(sample(angle: 0, timestamp: 4)))
    }

    func testCircularSessionReanchorPreventsStaleAngularJumpAcrossContacts() throws {
        var session = TVRemoteCircularScrubSession()
        XCTAssertTrue(session.begin(
            sample: sample(angle: 0, timestamp: 1),
            originalTime: 300,
            duration: 1_800,
            wasPlaying: true
        ))
        XCTAssertEqual(
            try XCTUnwrap(session.update(sample(angle: .pi / 2, timestamp: 2))),
            315,
            accuracy: 0.000_001
        )

        XCTAssertTrue(session.reanchor(sample(angle: -.pi / 2, timestamp: 10)))
        let target = try XCTUnwrap(session.update(sample(angle: 0, timestamp: 11)))

        XCTAssertEqual(target, 330, accuracy: 0.000_001)
    }

    func testGestureAdapterStateForwardsCancelledAndFailedButKeepsEndedPreview() {
        var state = TVRemoteCircularScrubGestureState()

        XCTAssertEqual(state.handle(.began), .beginSample)
        XCTAssertEqual(state.handle(.changed), .changeSample)
        XCTAssertEqual(state.handle(.ended), .none)
        XCTAssertEqual(state.handle(.began), .beginSample)
        XCTAssertEqual(state.handle(.cancelled), .cancel)
        XCTAssertEqual(state.handle(.failed), .cancel)
    }

    func testCircularSessionStressAlternatingDirectionsAndBounds() throws {
        let duration = 7_200.0

        for iteration in 0..<100 {
            var session = TVRemoteCircularScrubSession()
            let originalTime = iteration.isMultiple(of: 2) ? 0.0 : duration
            XCTAssertTrue(session.begin(
                sample: sample(angle: 0, timestamp: 0),
                originalTime: originalTime,
                duration: duration,
                wasPlaying: iteration.isMultiple(of: 3)
            ))

            let direction = iteration.isMultiple(of: 2) ? 1.0 : -1.0
            for step in 1...24 {
                let alternatingDirection = step.isMultiple(of: 2) ? -direction : direction
                let target = try XCTUnwrap(session.update(sample(
                    angle: alternatingDirection * Double(step) * .pi / 8,
                    timestamp: Double(step) / 120
                )))
                XCTAssertTrue(target.isFinite)
                XCTAssertGreaterThanOrEqual(target, 0)
                XCTAssertLessThanOrEqual(target, duration)
            }

            let resolution = try XCTUnwrap(iteration.isMultiple(of: 2) ? session.commit() : session.cancel())
            XCTAssertTrue(resolution.targetSeconds.isFinite)
            XCTAssertGreaterThanOrEqual(resolution.targetSeconds, 0)
            XCTAssertLessThanOrEqual(resolution.targetSeconds, duration)
        }
    }

    func testCircularScrubPreviewEvidenceUsesRoundedThirtySecondBuckets() {
        XCTAssertEqual(TVRemoteCircularScrubCoordinator.previewBucket(seconds: 0), "0")
        XCTAssertEqual(TVRemoteCircularScrubCoordinator.previewBucket(seconds: 14.9), "0")
        XCTAssertEqual(TVRemoteCircularScrubCoordinator.previewBucket(seconds: 15), "30")
        XCTAssertEqual(TVRemoteCircularScrubCoordinator.previewBucket(seconds: 314), "300")
        XCTAssertNil(TVRemoteCircularScrubCoordinator.previewBucket(seconds: nil))
        XCTAssertNil(TVRemoteCircularScrubCoordinator.previewBucket(seconds: .nan))
    }

    private func sample(
        angle: Double,
        radius: CGFloat = 40,
        timestamp: TimeInterval
    ) -> TVRemoteScrubSample {
        let center = CGPoint(x: 100, y: 100)
        return TVRemoteScrubSample(
            location: CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            ),
            center: center,
            timestamp: timestamp
        )
    }
}
