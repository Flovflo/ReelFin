import AVFoundation
import AVKit
import UIKit

#if os(tvOS)
final class NativeDisplayCriteriaCoordinator {
    private weak var viewController: UIViewController?
    private let lock = NSLock()
    private var generation = 0
    private var scheduledGeneration: Int?

    init(viewController: UIViewController) {
        self.viewController = viewController
    }

    func scheduleApply(from sample: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sample) else { return }
        guard let durationSeconds = Self.frameDurationSeconds(from: CMSampleBufferGetDuration(sample)) else { return }
        let targetGeneration: Int
        lock.lock()
        if scheduledGeneration == generation {
            lock.unlock()
            return
        }
        targetGeneration = generation
        scheduledGeneration = targetGeneration
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.apply(
                formatDescription: formatDescription,
                durationSeconds: durationSeconds,
                generation: targetGeneration
            )
        }
    }

    func reset() {
        lock.lock()
        generation += 1
        scheduledGeneration = nil
        lock.unlock()

        DispatchQueue.main.async { [weak viewController] in
            viewController?.viewIfLoaded?.window?.avDisplayManager.preferredDisplayCriteria = nil
        }
    }

    static func frameDurationSeconds(from duration: CMTime) -> Double? {
        guard duration.isValid, !duration.isIndefinite, !duration.isNegativeInfinity, !duration.isPositiveInfinity else {
            return nil
        }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    private func apply(
        formatDescription: CMFormatDescription,
        durationSeconds: Double,
        generation targetGeneration: Int
    ) {
        lock.lock()
        let isCurrent = generation == targetGeneration
        lock.unlock()
        guard isCurrent else { return }
        guard let window = viewController?.viewIfLoaded?.window else {
            markApplyFailed(for: targetGeneration)
            return
        }
        window.avDisplayManager.preferredDisplayCriteria = AVDisplayCriteria(
            refreshRate: Float(1.0 / durationSeconds),
            formatDescription: formatDescription
        )
    }

    private func markApplyFailed(for targetGeneration: Int) {
        lock.lock()
        if generation == targetGeneration, scheduledGeneration == targetGeneration {
            scheduledGeneration = nil
        }
        lock.unlock()
    }
}
#endif
