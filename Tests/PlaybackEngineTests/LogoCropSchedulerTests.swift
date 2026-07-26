#if os(iOS)
@testable import ReelFinUI
import UIKit
import XCTest

final class LogoCropSchedulerTests: XCTestCase {
    func testRunsAtMostTwoCropBodiesAndAdmitsOneForOne() async throws {
        let probe = BlockingLogoCropProbe()
        let scheduler = LogoCropScheduler { image, _ in
            probe.run(id: Int(image.size.width))
            return image
        }
        let tasks = (1 ... 5).map { id in
            Task { try await scheduler.crop(readableImage(id: id)) }
        }

        await probe.waitUntilStarted(count: 2)
        XCTAssertEqual(probe.startedIDs.count, 2)
        XCTAssertEqual(probe.maximumActiveCount, 2)

        probe.release(id: probe.startedIDs[0])
        await probe.waitUntilStarted(count: 3)
        XCTAssertEqual(probe.startedIDs.count, 3)
        XCTAssertEqual(probe.maximumActiveCount, 2)

        probe.releaseAll()
        for task in tasks {
            _ = try await task.value
        }
        XCTAssertEqual(probe.maximumActiveCount, 2)
    }

    func testCancelingQueuedCropReturnsBeforeActiveCropsFinishAndNeverStartsItsBody() async throws {
        let probe = BlockingLogoCropProbe()
        let scheduler = LogoCropScheduler { image, _ in
            probe.run(id: Int(image.size.width))
            return image
        }
        let first = Task { try await scheduler.crop(readableImage(id: 1)) }
        let second = Task { try await scheduler.crop(readableImage(id: 2)) }
        await probe.waitUntilStarted(count: 2)

        let queued = Task { try await scheduler.crop(readableImage(id: 3)) }
        await waitUntilOperationCount(3, scheduler: scheduler)
        queued.cancel()

        do {
            _ = try await queued.value
            XCTFail("Expected queued crop cancellation")
        } catch is CancellationError {
            // Expected while the two active bodies are still blocked.
        }
        XCTAssertFalse(probe.startedIDs.contains(3))

        probe.releaseAll()
        _ = try await first.value
        _ = try await second.value
    }

    func testCancelingActiveCropPropagatesIntoTransparentPixelScan() async {
        let scanProbe = BlockingScanCancellationProbe()
        let scheduler = LogoCropScheduler { image, isCancelled in
            let result = TransparentImageCropper.readableLogoImage(
                from: image,
                isCancelled: {
                    scanProbe.check(isCancelled: isCancelled)
                }
            )
            scanProbe.recordFinished(resultWasNil: result == nil)
            return result
        }
        let task = Task {
            try await scheduler.crop(readableImage(id: 512, height: 512))
        }
        await scanProbe.waitUntilScanStarted()

        task.cancel()

        let completion = expectation(description: "Canceled caller returns while crop scan stays blocked")
        let resultTask = Task { () -> Result<UIImage?, Error> in
            do {
                return .success(try await task.value)
            } catch {
                return .failure(error)
            }
        }
        let completionObserver = Task {
            _ = await resultTask.value
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 1)
        XCTAssertFalse(scanProbe.isFinished)

        scanProbe.releaseScan()
        let result = await resultTask.value
        _ = await completionObserver.value
        switch result {
        case let .failure(error) where error is CancellationError:
            break
        case let .failure(error):
            XCTFail("Unexpected error: \(error)")
        case .success:
            XCTFail("Expected active crop cancellation")
        }
        await scanProbe.waitUntilFinished()
        XCTAssertTrue(scanProbe.observedCancellation)
        XCTAssertTrue(scanProbe.resultWasNil)
    }

    func testCancellationBeforeOperationInstallationNeverStartsCropBody() async {
        let probe = ImmediateLogoCropProbe()
        let scheduler = LogoCropScheduler { image, _ in
            probe.recordStart()
            return image
        }
        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await scheduler.crop(readableImage(id: 48))
        }

        do {
            _ = try await task.value
            XCTFail("Expected pre-installation crop cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(probe.startCount, 0)
    }

    private func waitUntilOperationCount(
        _ expectedCount: Int,
        scheduler: LogoCropScheduler
    ) async {
        while scheduler.operationCount < expectedCount {
            await Task.yield()
        }
    }

    private func readableImage(id: Int, height: Int = 24) -> UIImage {
        let size = CGSize(width: id, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private final class BlockingLogoCropProbe: @unchecked Sendable {
    private struct StartWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let condition = NSCondition()
    private var startedStorage = [Int]()
    private var activeCount = 0
    private var maximumActiveCountStorage = 0
    private var releasedIDs = Set<Int>()
    private var releasesAll = false
    private var startWaiters = [StartWaiter]()

    var startedIDs: [Int] {
        condition.withLock { startedStorage }
    }

    var maximumActiveCount: Int {
        condition.withLock { maximumActiveCountStorage }
    }

    func run(id: Int) {
        let resumptions = condition.withLock {
            startedStorage.append(id)
            activeCount += 1
            maximumActiveCountStorage = max(maximumActiveCountStorage, activeCount)
            let ready = startWaiters.filter { $0.count <= startedStorage.count }
            startWaiters.removeAll { $0.count <= startedStorage.count }
            return ready.map(\.continuation)
        }
        resumptions.forEach { $0.resume() }

        condition.lock()
        while !releasesAll, !releasedIDs.contains(id) {
            condition.wait()
        }
        activeCount -= 1
        condition.unlock()
    }

    func waitUntilStarted(count: Int) async {
        if condition.withLock({ startedStorage.count >= count }) {
            return
        }
        await withCheckedContinuation { continuation in
            let resumeImmediately = condition.withLock {
                guard startedStorage.count < count else { return true }
                startWaiters.append(StartWaiter(count: count, continuation: continuation))
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    func release(id: Int) {
        condition.withLock {
            releasedIDs.insert(id)
            condition.broadcast()
        }
    }

    func releaseAll() {
        condition.withLock {
            releasesAll = true
            condition.broadcast()
        }
    }
}

private final class BlockingScanCancellationProbe: @unchecked Sendable {
    private let condition = NSCondition()
    private var scanStarted = false
    private var scanReleased = false
    private var finished = false
    private var observedCancellationStorage = false
    private var resultWasNilStorage = false
    private var scanWaiters = [CheckedContinuation<Void, Never>]()
    private var finishWaiters = [CheckedContinuation<Void, Never>]()

    var observedCancellation: Bool {
        condition.withLock { observedCancellationStorage }
    }

    var resultWasNil: Bool {
        condition.withLock { resultWasNilStorage }
    }

    var isFinished: Bool {
        condition.withLock { finished }
    }

    func check(isCancelled: @Sendable () -> Bool) -> Bool {
        let resumptions = condition.withLock {
            guard !scanStarted else { return [CheckedContinuation<Void, Never>]() }
            scanStarted = true
            let ready = scanWaiters
            scanWaiters.removeAll()
            return ready
        }
        resumptions.forEach { $0.resume() }

        condition.lock()
        while !scanReleased {
            condition.wait()
        }
        condition.unlock()

        let canceled = isCancelled()
        if canceled {
            condition.withLock {
                observedCancellationStorage = true
            }
        }
        return canceled
    }

    func waitUntilScanStarted() async {
        if condition.withLock({ scanStarted }) {
            return
        }
        await withCheckedContinuation { continuation in
            let resumeImmediately = condition.withLock {
                guard !scanStarted else { return true }
                scanWaiters.append(continuation)
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    func releaseScan() {
        condition.withLock {
            scanReleased = true
            condition.broadcast()
        }
    }

    func recordFinished(resultWasNil: Bool) {
        let resumptions = condition.withLock {
            self.resultWasNilStorage = resultWasNil
            finished = true
            let ready = finishWaiters
            finishWaiters.removeAll()
            return ready
        }
        resumptions.forEach { $0.resume() }
    }

    func waitUntilFinished() async {
        if condition.withLock({ finished }) {
            return
        }
        await withCheckedContinuation { continuation in
            let resumeImmediately = condition.withLock {
                guard !finished else { return true }
                finishWaiters.append(continuation)
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }
}

private final class ImmediateLogoCropProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var startCountStorage = 0

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return startCountStorage
    }

    func recordStart() {
        lock.lock()
        startCountStorage += 1
        lock.unlock()
    }
}

private extension NSCondition {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
#endif
