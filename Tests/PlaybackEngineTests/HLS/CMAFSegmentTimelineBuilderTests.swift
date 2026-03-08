@testable import PlaybackEngine
import CoreMedia
import XCTest

final class CMAFSegmentTimelineBuilderTests: XCTestCase {
    func testBuildCreatesMonotonicSegments() {
        var samples: [Sample] = []
        let frameNs: Int64 = 41_708_333
        for idx in 0..<120 {
            let pts = Int64(idx) * frameNs
            samples.append(
                Sample(
                    trackID: 1,
                    pts: CMTime(value: pts, timescale: 1_000_000_000),
                    duration: CMTime(value: frameNs, timescale: 1_000_000_000),
                    isKeyframe: idx % 24 == 0,
                    data: Data([0x00, 0x01])
                )
            )
        }

        let result = CMAFSegmentTimelineBuilder().build(samples: samples, targetDurationSeconds: 2.0)

        XCTAssertFalse(result.segments.isEmpty)
        XCTAssertGreaterThanOrEqual(result.targetDurationSeconds, 1)

        let starts = result.segments.map(\.startPTS)
        XCTAssertEqual(starts, starts.sorted())
        XCTAssertTrue(result.segments.allSatisfy { $0.durationNs > 0 })
    }
}
