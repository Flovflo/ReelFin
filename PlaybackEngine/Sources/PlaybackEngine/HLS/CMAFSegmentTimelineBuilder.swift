import Foundation

public struct CMAFSegmentTimelineEntry: Sendable, Equatable {
    public let sequence: Int
    public let startPTS: Int64
    public let durationNs: Int64
    public let sampleRange: Range<Int>
    public let startsWithKeyframe: Bool

    public init(sequence: Int, startPTS: Int64, durationNs: Int64, sampleRange: Range<Int>, startsWithKeyframe: Bool) {
        self.sequence = sequence
        self.startPTS = startPTS
        self.durationNs = durationNs
        self.sampleRange = sampleRange
        self.startsWithKeyframe = startsWithKeyframe
    }
}

public struct CMAFSegmentTimelineBuildResult: Sendable, Equatable {
    public let segments: [CMAFSegmentTimelineEntry]
    public let targetDurationSeconds: Int

    public init(segments: [CMAFSegmentTimelineEntry], targetDurationSeconds: Int) {
        self.segments = segments
        self.targetDurationSeconds = targetDurationSeconds
    }
}

public struct CMAFSegmentTimelineBuilder: Sendable {
    public init() {}

    public func build(samples: [Sample], targetDurationSeconds: Double) -> CMAFSegmentTimelineBuildResult {
        guard !samples.isEmpty else {
            return CMAFSegmentTimelineBuildResult(segments: [], targetDurationSeconds: max(1, Int(targetDurationSeconds.rounded(.up))))
        }

        let targetNs = Int64(targetDurationSeconds * 1_000_000_000.0)
        let safeTargetNs = max(Int64(1_000_000_000), targetNs)

        var segments: [CMAFSegmentTimelineEntry] = []
        var currentStartIndex = 0
        var currentStartPTS = samples[0].ptsNanoseconds
        var accumulated: Int64 = 0
        var sequence = 0

        for index in samples.indices {
            accumulated += max(0, samples[index].durationNanoseconds)
            let isBoundaryCandidate = index > currentStartIndex && samples[index].isKeyframe
            let reachedTarget = accumulated >= safeTargetNs
            let isLast = index == samples.index(before: samples.endIndex)

            if (reachedTarget && isBoundaryCandidate) || isLast {
                let endExclusive = isLast ? samples.endIndex : index
                if endExclusive > currentStartIndex {
                    let duration = samples[currentStartIndex..<endExclusive]
                        .reduce(Int64(0)) { $0 + max(0, $1.durationNanoseconds) }
                    segments.append(
                        CMAFSegmentTimelineEntry(
                            sequence: sequence,
                            startPTS: currentStartPTS,
                            durationNs: duration,
                            sampleRange: currentStartIndex..<endExclusive,
                            startsWithKeyframe: samples[currentStartIndex].isKeyframe
                        )
                    )
                    sequence += 1
                }

                currentStartIndex = endExclusive
                if currentStartIndex < samples.endIndex {
                    currentStartPTS = samples[currentStartIndex].ptsNanoseconds
                }
                accumulated = 0
            }
        }

        // If no segment was emitted because all samples were tiny and no keyframe split happened.
        if segments.isEmpty {
            let duration = samples.reduce(Int64(0)) { $0 + max(0, $1.durationNanoseconds) }
            segments.append(
                CMAFSegmentTimelineEntry(
                    sequence: 0,
                    startPTS: samples[0].ptsNanoseconds,
                    durationNs: duration,
                    sampleRange: samples.startIndex..<samples.endIndex,
                    startsWithKeyframe: samples[0].isKeyframe
                )
            )
        }

        let maxDurationNs = segments.map(\ .durationNs).max() ?? safeTargetNs
        let targetSeconds = max(1, Int(ceil(Double(maxDurationNs) / 1_000_000_000.0)))
        return CMAFSegmentTimelineBuildResult(segments: segments, targetDurationSeconds: targetSeconds)
    }
}
