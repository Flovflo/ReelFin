import CoreGraphics
import Foundation

struct TVRemoteScrubSample: Equatable, Sendable {
    let location: CGPoint
    let center: CGPoint
    let timestamp: TimeInterval

    fileprivate var isFinite: Bool {
        location.x.isFinite && location.y.isFinite
            && center.x.isFinite && center.y.isFinite
            && timestamp.isFinite
    }
}

struct TVRemoteScrubResolution: Equatable, Sendable {
    let targetSeconds: Double
    let wasPlaying: Bool
}

enum TVRemoteCircularScrubPolicy {
    static let centerDeadZoneRadius: CGFloat = 18

    static func angularDelta(
        previous: TVRemoteScrubSample,
        current: TVRemoteScrubSample
    ) -> Double? {
        guard previous.isFinite, current.isFinite else { return nil }
        let previousVector = CGPoint(
            x: previous.location.x - previous.center.x,
            y: previous.location.y - previous.center.y
        )
        let currentVector = CGPoint(
            x: current.location.x - current.center.x,
            y: current.location.y - current.center.y
        )
        guard hypot(previousVector.x, previousVector.y) >= centerDeadZoneRadius,
              hypot(currentVector.x, currentVector.y) >= centerDeadZoneRadius else {
            return nil
        }
        let previousAngle = atan2(previousVector.y, previousVector.x)
        let currentAngle = atan2(currentVector.y, currentVector.x)
        var delta = currentAngle - previousAngle
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return delta
    }

    static func secondsPerRevolution(duration: Double) -> Double {
        guard duration.isFinite else { return 30 }
        return min(max(duration / 30, 30), 300)
    }

    static func velocityMultiplier(radiansPerSecond: Double) -> Double {
        guard radiansPerSecond.isFinite else { return 1 }
        return switch abs(radiansPerSecond) {
        case ..<0.6: 0.5
        case ..<2.2: 1
        case ..<4.0: 2
        default: 4
        }
    }

    static func target(
        original: Double,
        weightedRadians: Double,
        duration: Double
    ) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        let clampedOriginal = original.isFinite ? min(max(original, 0), duration) : 0
        guard weightedRadians.isFinite else { return clampedOriginal }
        let seconds = (weightedRadians / (2 * .pi)) * secondsPerRevolution(duration: duration)
        guard seconds.isFinite else { return weightedRadians < 0 ? 0 : duration }
        let candidate = clampedOriginal + seconds
        guard candidate.isFinite else { return seconds < 0 ? 0 : duration }
        return min(max(candidate, 0), duration)
    }
}

struct TVRemoteCircularScrubSession: Equatable, Sendable {
    struct Preview: Equatable, Sendable {
        var originalTime: Double
        var targetTime: Double
        var duration: Double
        var wasPlaying: Bool
        var weightedRadians: Double
        var previousSample: TVRemoteScrubSample
    }

    enum Phase: Equatable, Sendable {
        case idle
        case preview(Preview)
    }

    private(set) var phase: Phase = .idle

    mutating func begin(
        sample: TVRemoteScrubSample,
        originalTime: Double,
        duration: Double,
        wasPlaying: Bool
    ) -> Bool {
        guard case .idle = phase,
              sample.isFinite,
              duration.isFinite, duration > 0,
              originalTime.isFinite else { return false }
        let clampedOriginal = min(max(originalTime, 0), duration)
        phase = .preview(Preview(
            originalTime: clampedOriginal,
            targetTime: clampedOriginal,
            duration: duration,
            wasPlaying: wasPlaying,
            weightedRadians: 0,
            previousSample: sample
        ))
        return true
    }

    mutating func update(_ sample: TVRemoteScrubSample) -> Double? {
        guard case var .preview(preview) = phase else { return nil }
        let elapsed = sample.timestamp - preview.previousSample.timestamp
        guard sample.isFinite, elapsed.isFinite, elapsed > 0 else {
            return preview.targetTime
        }
        defer { preview.previousSample = sample; phase = .preview(preview) }
        guard let delta = TVRemoteCircularScrubPolicy.angularDelta(
            previous: preview.previousSample,
            current: sample
        ) else { return preview.targetTime }
        let multiplier = TVRemoteCircularScrubPolicy.velocityMultiplier(
            radiansPerSecond: delta / max(elapsed, 1.0 / 120.0)
        )
        let weightedRadians = preview.weightedRadians + delta * multiplier
        guard weightedRadians.isFinite else { return preview.targetTime }
        preview.weightedRadians = weightedRadians
        preview.targetTime = TVRemoteCircularScrubPolicy.target(
            original: preview.originalTime,
            weightedRadians: preview.weightedRadians,
            duration: preview.duration
        )
        return preview.targetTime
    }

    mutating func commit() -> TVRemoteScrubResolution? {
        guard case let .preview(preview) = phase else { return nil }
        phase = .idle
        return TVRemoteScrubResolution(
            targetSeconds: preview.targetTime,
            wasPlaying: preview.wasPlaying
        )
    }

    mutating func cancel() -> TVRemoteScrubResolution? {
        guard case let .preview(preview) = phase else { return nil }
        phase = .idle
        return TVRemoteScrubResolution(
            targetSeconds: preview.originalTime,
            wasPlaying: preview.wasPlaying
        )
    }
}
