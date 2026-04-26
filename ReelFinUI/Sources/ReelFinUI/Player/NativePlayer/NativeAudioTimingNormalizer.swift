import CoreMedia
import Foundation

struct NativeAudioTimingNormalizationResult {
    var sampleBuffer: CMSampleBuffer
    var rewrotePresentationTimestamp: Bool
    var ptsCorrectionSeconds: Double
}

struct NativeAudioTimingNormalizer {
    private var lastPTS: CMTime?
    private var lastDuration: CMTime?
    private let tolerance = CMTime(value: 2, timescale: 1000)

    mutating func reset() {
        lastPTS = nil
        lastDuration = nil
    }

    mutating func normalized(_ sample: CMSampleBuffer) throws -> NativeAudioTimingNormalizationResult {
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let duration = validDuration(for: sample)
        guard let lastPTS, let lastDuration, let duration else {
            remember(pts: pts, duration: duration)
            return NativeAudioTimingNormalizationResult(
                sampleBuffer: sample,
                rewrotePresentationTimestamp: false,
                ptsCorrectionSeconds: 0
            )
        }

        let expectedPTS = lastPTS + lastDuration
        let shouldRewrite = !pts.isValid || abs((pts - expectedPTS).seconds) > tolerance.seconds
        guard shouldRewrite else {
            remember(pts: pts, duration: duration)
            return NativeAudioTimingNormalizationResult(
                sampleBuffer: sample,
                rewrotePresentationTimestamp: false,
                ptsCorrectionSeconds: 0
            )
        }

        let rewritten = try copy(sample, pts: expectedPTS, duration: duration)
        let correction = pts.isValid ? abs((pts - expectedPTS).seconds) : 0
        remember(pts: expectedPTS, duration: duration)
        return NativeAudioTimingNormalizationResult(
            sampleBuffer: rewritten,
            rewrotePresentationTimestamp: true,
            ptsCorrectionSeconds: correction.isFinite ? correction : 0
        )
    }

    private mutating func remember(pts: CMTime, duration: CMTime?) {
        if pts.isValid {
            lastPTS = pts
        }
        if let duration {
            lastDuration = duration
        }
    }

    private func validDuration(for sample: CMSampleBuffer) -> CMTime? {
        let duration = CMSampleBufferGetDuration(sample)
        guard duration.isValid, !duration.isIndefinite, duration.seconds.isFinite, duration.seconds > 0 else {
            return lastDuration
        }
        return duration
    }

    private func copy(_ sample: CMSampleBuffer, pts: CMTime, duration: CMTime) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var rewritten: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sample,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &rewritten
        )
        guard status == noErr, let rewritten else {
            throw NativeAudioTimingNormalizerError.copyFailed(status)
        }
        return rewritten
    }
}

enum NativeAudioTimingNormalizerError: LocalizedError {
    case copyFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .copyFailed(status):
            return "Audio timing normalization failed while copying CMSampleBuffer: \(status)."
        }
    }
}
